#ifndef TDLibBridge_h
#define TDLibBridge_h
// Official TDLib JSON C interface: td/telegram/td_json_client.h.
// The TDLibFramework Swift package supplies these symbols at link time.
void *td_json_client_create(void);
void td_json_client_send(void *client, const char *request);
const char *td_json_client_receive(void *client, double timeout);
const char *td_json_client_execute(void *client, const char *request);
void td_json_client_destroy(void *client);
#endif

