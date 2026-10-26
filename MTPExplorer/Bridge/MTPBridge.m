#import <Foundation/Foundation.h>
#include <libmtp.h>
#include <sys/stat.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include "MTPBridge.h"

struct MTPConnection { LIBMTP_mtpdevice_t *device; };
static char errorMessage[2048];
static void setError(const char *message) { snprintf(errorMessage, sizeof(errorMessage), "%s", message); }
static void captureError(MTPConnection *c, const char *fallback) {
    LIBMTP_error_t *e = LIBMTP_Get_Errorstack(c->device);
    setError(e && e->error_text ? e->error_text : fallback);
    LIBMTP_Clear_Errorstack(c->device);
}
static NSString *string(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"") : @""; }
// Query both the USB device and MTP interface: macOS can assign them to
// different owners (e.g. adb at device level and ptpcamerad at interface level).
static id registryProperty(io_registry_entry_t entry, CFStringRef key) {
    return CFBridgingRelease(IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0));
}
int32_t mtp_camera_owner_pid(const char *owner) {
    if (!owner) return 0;
    int pid = 0; char process[64] = {0}, extra = 0;
    if (sscanf(owner, "pid %d, %63s %c", &pid, process, &extra) != 2 || pid <= 1 || strcmp(process, "ptpcamerad") != 0) return 0;
    return pid;
}
static NSDictionary *usbDeviceInfo(uint32_t bus, uint8_t address) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) != KERN_SUCCESS) return @{};
    NSDictionary *result = @{};
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        NSNumber *location = registryProperty(entry, CFSTR("locationID"));
        NSNumber *usbAddress = registryProperty(entry, CFSTR("USB Address"));
        if (!usbAddress) usbAddress = registryProperty(entry, CFSTR("kUSBAddress"));
        if (location && usbAddress && (location.unsignedIntValue >> 24) == bus && usbAddress.unsignedIntValue == address) {
            NSString *name = registryProperty(entry, CFSTR("USB Product Name"));
            if (![name isKindOfClass:NSString.class] || name.length == 0) {
                io_name_t registryName = {0};
                if (IORegistryEntryGetName(entry, registryName) == KERN_SUCCESS) name = string(registryName);
            }
            NSMutableArray *owners = [NSMutableArray array];
            NSString *owner = registryProperty(entry, CFSTR("UsbExclusiveOwner"));
            if ([owner isKindOfClass:NSString.class] && owner.length) [owners addObject:owner];
            int32_t cameraPID = 0;
            io_iterator_t children = IO_OBJECT_NULL;
            if (IORegistryEntryCreateIterator(entry, kIOServicePlane, kIORegistryIterateRecursively, &children) == KERN_SUCCESS) {
                io_registry_entry_t child;
                while ((child = IOIteratorNext(children))) {
                    NSNumber *interfaceClass = registryProperty(child, CFSTR("bInterfaceClass"));
                    io_name_t interfaceName = {0}; IORegistryEntryGetName(child, interfaceName);
                    if (interfaceClass && (interfaceClass.intValue == 6 || [string(interfaceName) localizedCaseInsensitiveContainsString:@"MTP"])) {
                        NSString *interfaceOwner = registryProperty(child, CFSTR("UsbExclusiveOwner"));
                        if ([interfaceOwner isKindOfClass:NSString.class] && interfaceOwner.length) {
                            if (![owners containsObject:interfaceOwner]) [owners addObject:interfaceOwner];
                            int32_t candidate = mtp_camera_owner_pid(interfaceOwner.UTF8String);
                            if (candidate) cameraPID = candidate;
                        }
                    }
                    IOObjectRelease(child);
                }
                IOObjectRelease(children);
            }
            result = @{@"name": name ?: @"", @"owners": owners, @"cameraPID": @(cameraPID)};
            IOObjectRelease(entry); break;
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return result;
}
bool mtp_camera_busy(uint32_t bus, uint8_t address) {
    return [usbDeviceInfo(bus, address)[@"cameraPID"] intValue] > 1;
}
static void connectionError(uint32_t bus, uint8_t address) {
    NSDictionary *info = usbDeviceInfo(bus, address);
    NSArray *owners = info[@"owners"];
    NSString *message;
    if (owners.count) {
        message = [NSString stringWithFormat:@"设备或 MTP 接口正被其他进程占用：\n%@\n\n请先结束对应应用的设备会话，再重试连接。", [owners componentsJoinedByString:@"\n"]];
        if ([info[@"cameraPID"] intValue] > 1) message = [message stringByAppendingString:@"\n\n可点击“释放相机占用并重试”。这会结束系统相机服务当前会话，可能中断照片导入，不会修改系统设置。"];
    } else {
        message = @"无法建立 MTP 会话。请解锁设备并选择“文件传输 / MTP”，确认允许访问后重试。若刚关闭占用进程，请重新插拔 USB 数据线。";
    }
    setError(message.UTF8String);
}
static char *json(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:nil];
    if (!data) { setError("Unable to encode device response"); return NULL; }
    return strndup(data.bytes, data.length);
}
const char *mtp_error(void) { return errorMessage; }
void mtp_free(char *s) { free(s); }
char *mtp_scan(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ LIBMTP_Init(); });
    LIBMTP_raw_device_t *raw = NULL;
    int count = 0;
    LIBMTP_error_number_t status = LIBMTP_Detect_Raw_Devices(&raw, &count);
    if (status == LIBMTP_ERROR_NO_DEVICE_ATTACHED) { free(raw); return json(@[]); }
    if (status != LIBMTP_ERROR_NONE) { free(raw); setError("USB device discovery failed"); return NULL; }
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        NSDictionary *info = usbDeviceInfo(raw[i].bus_location, raw[i].devnum);
        NSString *name = info[@"name"];
        if (!name.length) name = string(raw[i].device_entry.product);
        NSArray *owners = info[@"owners"] ?: @[];
        NSString *accessIssue = [info[@"cameraPID"] intValue] > 1 ? @"系统相机服务占用" : (owners.count ? @"USB 正被其他进程使用" : @"");
        [items addObject:@{@"id": [NSString stringWithFormat:@"%u:%u", raw[i].bus_location, raw[i].devnum],
                          @"name": name.length ? name : @"MTP Device", @"bus": @(raw[i].bus_location), @"address": @(raw[i].devnum), @"accessIssue": accessIssue}];
    }
    free(raw);
    return json(items);
}
MTPConnection *mtp_connect(uint32_t bus, uint8_t address) {
    LIBMTP_raw_device_t *raw = NULL; int count = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE) {
        free(raw); setError("设备已断开连接，请检查 USB 数据线。"); return NULL;
    }
    LIBMTP_mtpdevice_t *device = NULL;
    for (int i = 0; i < count; i++) {
        if (raw[i].bus_location == bus && raw[i].devnum == address) {
            device = LIBMTP_Open_Raw_Device_Uncached(&raw[i]); break;
        }
    }
    free(raw);
    if (!device) { connectionError(bus, address); return NULL; }
    MTPConnection *c = calloc(1, sizeof(MTPConnection)); c->device = device; return c;
}
MTPConnection *mtp_connect_releasing_camera(uint32_t bus, uint8_t address) {
    int32_t pid = [usbDeviceInfo(bus, address)[@"cameraPID"] intValue];
    if (pid > 1) {
        // Never signal a PID based on its display name alone. Check the binary,
        // owning user, and current interface ownership again to handle PID reuse.
        char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        struct proc_bsdinfo process = {0};
        int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, sizeof(process));
        if (proc_pidpath(pid, path, sizeof(path)) <= 0 || strcmp(path, "/usr/libexec/ptpcamerad") != 0 ||
            size != sizeof(process) || process.pbi_uid != getuid() ||
            [usbDeviceInfo(bus, address)[@"cameraPID"] intValue] != pid) {
            setError("无法确认相机占用进程的身份，未结束任何进程。请关闭照片导入应用并重新连接设备。"); return NULL;
        }
        // ptpcamerad can ignore SIGTERM. Release only this confirmed owner,
        // never disable launchd services or repeatedly terminate a daemon.
        if (kill(pid, SIGKILL) != 0 && errno != ESRCH) {
            setError("无法释放系统相机服务的设备会话。请关闭照片导入应用后重试。"); return NULL;
        }
        // Wait for the kernel to drop the dead process's USB interface handle.
        // This bridge is only called on MTPService's background executor.
        for (int attempt = 0; attempt < 50; attempt++) {
            if (kill(pid, 0) != 0 && errno == ESRCH) break;
            usleep(10000);
        }
    }
    return mtp_connect(bus, address);
}
void mtp_disconnect(MTPConnection *c) { if (c) { LIBMTP_Release_Device(c->device); free(c); } }
char *mtp_name(MTPConnection *c) {
    char *name = LIBMTP_Get_Friendlyname(c->device);
    if (!name) name = LIBMTP_Get_Modelname(c->device);
    char *result = strdup(name ?: "MTP Device"); free(name); return result;
}
char *mtp_storages(MTPConnection *c) {
    LIBMTP_Clear_Errorstack(c->device);
    if (LIBMTP_Get_Storage(c->device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) { captureError(c, "Cannot read storage"); return NULL; }
    NSMutableArray *items = [NSMutableArray array];
    for (LIBMTP_devicestorage_t *s = c->device->storage; s; s = s->next) {
        [items addObject:@{@"id": @(s->id), @"name": string(s->StorageDescription), @"capacity": @(s->MaxCapacity),
                          @"free": @(s->FreeSpaceInBytes), @"writable": (s->AccessCapability == 0 ? @YES : @NO)}];
    }
    return json(items);
}
char *mtp_list(MTPConnection *c, uint32_t storage, uint32_t parent) {
    LIBMTP_Clear_Errorstack(c->device);
    uint32_t *children = NULL;
    int count = LIBMTP_Get_Children(c->device, storage, parent == 0 ? LIBMTP_FILES_AND_FOLDERS_ROOT : parent, &children);
    if (count < 0 || LIBMTP_Get_Errorstack(c->device)) { free(children); captureError(c, "Cannot list folder"); return NULL; }
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        LIBMTP_file_t *f = LIBMTP_Get_Filemetadata(c->device, children[i]);
        if (!f) { free(children); captureError(c, "Cannot read file metadata"); return NULL; }
        [items addObject:@{@"id": @(f->item_id), @"parent": @(f->parent_id), @"storage": @(f->storage_id),
                          @"name": string(f->filename), @"size": @(f->filesize), @"modified": @((int64_t)f->modificationdate),
                          @"isFolder": (f->filetype == LIBMTP_FILETYPE_FOLDER ? @YES : @NO)}];
        LIBMTP_destroy_file_t(f);
    }
    free(children); return json(items);
}
struct ProgressContext { MTPProgress callback; void *context; };
static int report(uint64_t done, uint64_t total, const void *opaque) {
    const struct ProgressContext *p = opaque;
    return p->callback ? p->callback(done, total, p->context) : 0;
}
bool mtp_download(MTPConnection *c, uint32_t object, const char *path, MTPProgress callback, void *context) {
    LIBMTP_Clear_Errorstack(c->device);
    struct ProgressContext p = { callback, context };
    if (LIBMTP_Get_File_To_File(c->device, object, path, report, &p) != 0) { captureError(c, "Download failed or was cancelled"); return false; }
    return true;
}
bool mtp_upload(MTPConnection *c, uint32_t storage, uint32_t parent, const char *path, const char *name, MTPProgress callback, void *context) {
    struct stat info;
    if (stat(path, &info) != 0) { setError("Cannot read local file"); return false; }
    LIBMTP_Clear_Errorstack(c->device);
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    file->filename = strdup(name); file->filesize = info.st_size;
    file->parent_id = parent; file->storage_id = storage;
    file->filetype = LIBMTP_FILETYPE_UNKNOWN; file->modificationdate = info.st_mtime;
    struct ProgressContext p = { callback, context };
    int result = LIBMTP_Send_File_From_File(c->device, path, file, report, &p);
    if (result != 0) {
        captureError(c, "Upload failed or was cancelled");
        if (file->item_id) LIBMTP_Delete_Object(c->device, file->item_id);
    }
    LIBMTP_destroy_file_t(file); return result == 0;
}
uint32_t mtp_mkdir(MTPConnection *c, uint32_t storage, uint32_t parent, const char *name) {
    LIBMTP_Clear_Errorstack(c->device);
    char *copy = strdup(name);
    uint32_t id = LIBMTP_Create_Folder(c->device, copy, parent, storage); free(copy);
    if (!id) captureError(c, "Cannot create folder"); return id;
}
bool mtp_rename(MTPConnection *c, uint32_t object, const char *name) {
    LIBMTP_Clear_Errorstack(c->device);
    LIBMTP_file_t *file = LIBMTP_Get_Filemetadata(c->device, object);
    if (!file) { captureError(c, "Cannot read object"); return false; }
    int result = LIBMTP_Set_File_Name(c->device, file, name);
    LIBMTP_destroy_file_t(file);
    if (result != 0) captureError(c, "Cannot rename object"); return result == 0;
}
bool mtp_delete(MTPConnection *c, uint32_t object) {
    LIBMTP_Clear_Errorstack(c->device);
    int result = LIBMTP_Delete_Object(c->device, object);
    if (result != 0) captureError(c, "Cannot delete object"); return result == 0;
}
