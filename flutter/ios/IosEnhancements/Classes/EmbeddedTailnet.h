#include <stdint.h>

char *rd_tailnet_start(const char *directory, const char *config, const uint8_t *key, int length);
char *rd_tailnet_stop(void);
char *rd_tailnet_status(void);
int rd_tailnet_port(int role, const char *target);
void rd_tailnet_free(char *value);
