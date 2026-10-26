#ifndef MTPBridge_h
#define MTPBridge_h
#include <stdint.h>
#include <stdbool.h>
typedef struct MTPConnection MTPConnection;
typedef int (*MTPProgress)(uint64_t completed, uint64_t total, void *context);
// Returned JSON strings are owned by the caller; release with mtp_free.
char *mtp_scan(void);
MTPConnection *mtp_connect(uint32_t bus, uint8_t address);
// Only call after an explicit user request to release the system camera session.
MTPConnection *mtp_connect_releasing_camera(uint32_t bus, uint8_t address);
bool mtp_camera_busy(uint32_t bus, uint8_t address);
// Strict parser; process identity is independently verified before any signal.
int32_t mtp_camera_owner_pid(const char *owner);
void mtp_disconnect(MTPConnection *connection);
char *mtp_name(MTPConnection *connection);
char *mtp_storages(MTPConnection *connection);
char *mtp_list(MTPConnection *connection, uint32_t storage, uint32_t parent);
bool mtp_download(MTPConnection *connection, uint32_t object, const char *path, MTPProgress progress, void *context);
bool mtp_upload(MTPConnection *connection, uint32_t storage, uint32_t parent, const char *path, const char *name, MTPProgress progress, void *context);
uint32_t mtp_mkdir(MTPConnection *connection, uint32_t storage, uint32_t parent, const char *name);
bool mtp_rename(MTPConnection *connection, uint32_t object, const char *name);
bool mtp_delete(MTPConnection *connection, uint32_t object);
const char *mtp_error(void);
void mtp_free(char *string);
#endif
