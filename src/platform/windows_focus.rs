use base::message_proto::{RemoteAppWindow, RemoteWindowSnapshot};
use std::{
    mem,
    path::Path,
    time::{Duration, Instant},
};
use winapi::{
    shared::{
        minwindef::{BOOL, DWORD, FALSE, LPARAM, TRUE},
        ntdef::HRESULT,
        windef::{HWND, RECT},
    },
    um::{
        handleapi::CloseHandle, processthreadsapi::OpenProcess,
        winbase::QueryFullProcessImageNameW, winnt::PROCESS_QUERY_LIMITED_INFORMATION, winuser,
    },
};

#[link(name = "dwmapi")]
extern "system" {
    fn DwmGetWindowAttribute(
        window: HWND,
        attribute: DWORD,
        output: *mut std::ffi::c_void,
        size: DWORD,
    ) -> HRESULT;
}

const MAX_WINDOWS: usize = 100;
const EXTENDED_FRAME_BOUNDS: DWORD = 9;
const CLOAKED: DWORD = 14;

#[derive(Default)]
pub(crate) struct WindowSnapshots(Option<Instant>);

impl WindowSnapshots {
    pub(crate) fn accept_request(&mut self) -> bool {
        if self
            .0
            .is_some_and(|last| last.elapsed() < Duration::from_millis(750))
        {
            return false;
        }
        self.0 = Some(Instant::now());
        true
    }
}

pub(crate) fn snapshot() -> RemoteWindowSnapshot {
    let mut windows = Vec::new();
    if super::windows_touch::on_default_input_desktop() {
        let result = unsafe {
            winuser::EnumWindows(
                Some(collect_window),
                (&mut windows as *mut Vec<RemoteAppWindow>) as LPARAM,
            )
        };
        if result == FALSE && windows.len() < MAX_WINDOWS {
            hbb_common::throttled_log!(
                Duration::from_secs(5),
                warn,
                "Could not enumerate windows: {}",
                std::io::Error::last_os_error()
            );
        }
    }
    RemoteWindowSnapshot {
        windows,
        ..Default::default()
    }
}

unsafe extern "system" fn collect_window(window: HWND, data: LPARAM) -> BOOL {
    let windows = &mut *(data as *mut Vec<RemoteAppWindow>);
    if let Some(info) = window_info(window) {
        windows.push(info);
    }
    if windows.len() < MAX_WINDOWS {
        TRUE
    } else {
        FALSE
    }
}

unsafe fn window_info(window: HWND) -> Option<RemoteAppWindow> {
    if winuser::IsWindowVisible(window) == FALSE
        || winuser::IsIconic(window) != FALSE
        || window == winuser::GetShellWindow()
        || winuser::GetWindowLongW(window, winuser::GWL_EXSTYLE) & winuser::WS_EX_TOOLWINDOW as i32
            != 0
        || winuser::MonitorFromWindow(window, winuser::MONITOR_DEFAULTTONULL).is_null()
    {
        return None;
    }
    let mut cloaked = 0u32;
    if DwmGetWindowAttribute(
        window,
        CLOAKED,
        (&mut cloaked as *mut u32).cast(),
        mem::size_of_val(&cloaked) as DWORD,
    ) >= 0
        && cloaked != 0
    {
        return None;
    }
    let mut title = [0u16; 256];
    let length = winuser::GetWindowTextW(window, title.as_mut_ptr(), title.len() as i32);
    if length <= 0 {
        return None;
    }

    let mut bounds: RECT = mem::zeroed();
    if DwmGetWindowAttribute(
        window,
        EXTENDED_FRAME_BOUNDS,
        (&mut bounds as *mut RECT).cast(),
        mem::size_of_val(&bounds) as DWORD,
    ) < 0
        && winuser::GetWindowRect(window, &mut bounds) == FALSE
    {
        return None;
    }
    let width = u32::try_from(i64::from(bounds.right) - i64::from(bounds.left)).ok()?;
    let height = u32::try_from(i64::from(bounds.bottom) - i64::from(bounds.top)).ok()?;
    if width == 0 || height == 0 {
        return None;
    }
    let mut pid = 0;
    if winuser::GetWindowThreadProcessId(window, &mut pid) == 0 {
        return None;
    }
    Some(RemoteAppWindow {
        id: format!("{}:{pid}", window as usize),
        title: String::from_utf16_lossy(&title[..length as usize]),
        app: process_name(pid),
        x: bounds.left,
        y: bounds.top,
        width,
        height,
        ..Default::default()
    })
}

unsafe fn process_name(pid: DWORD) -> String {
    let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if process.is_null() {
        return String::new();
    }
    let mut path = [0u16; 1024];
    let mut length = path.len() as DWORD;
    let found = QueryFullProcessImageNameW(process, 0, path.as_mut_ptr(), &mut length);
    CloseHandle(process);
    if found == FALSE {
        return String::new();
    }
    let path = String::from_utf16_lossy(&path[..length as usize]);
    Path::new(&path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_owned()
}
