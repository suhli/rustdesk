#import "GeneratedPluginRegistrant.h"

#import "bridge_generated.h"
#include <stddef.h>
#include <stdint.h>

typedef void (*RdIosPiPFrameSink)(size_t display, const uint8_t *bytes,
                                 size_t width, size_t height, size_t stride);
void rd_ios_pip_register_frame_sink(RdIosPiPFrameSink sink);
