use scrap::{ImageFormat, ImageRgb};
use std::sync::OnceLock;

type FrameSink = extern "C" fn(usize, *const u8, usize, usize, usize);
static FRAME_SINK: OnceLock<FrameSink> = OnceLock::new();

#[no_mangle]
pub extern "C" fn rd_ios_pip_register_frame_sink(sink: FrameSink) {
    FRAME_SINK.get_or_init(|| sink);
}

pub(crate) fn submit(display: usize, frame: &ImageRgb) {
    let Some(sink) = FRAME_SINK.get() else { return };
    if !matches!(frame.fmt, ImageFormat::ARGB) || frame.h == 0 || frame.w == 0 {
        return;
    }
    let stride = frame.raw.len() / frame.h;
    if stride / 4 >= frame.w && frame.raw.len() % frame.h == 0 {
        // libyuv's ARGB byte order on iOS is BGRA. The sink borrows it only for this call.
        sink(display, frame.raw.as_ptr(), frame.w, frame.h, stride);
    }
}
