use base::message_proto::{native_touch_contact::Phase, NativeTouchContact, PointerDeviceEvent};
use std::{
    collections::BTreeMap,
    io, mem,
    sync::{Mutex, OnceLock},
    time::Duration,
};
use winapi::{
    shared::{
        minwindef::{BOOL, DWORD, FALSE, UINT},
        ntdef::LONG,
        windef::POINT,
        winerror::ERROR_NOT_READY,
    },
    um::{
        libloaderapi::{GetModuleHandleA, GetProcAddress},
        winuser::{self, POINTER_TOUCH_INFO},
    },
};

const MAX_CONTACTS: usize = 10;
const CAPABILITY: &str = "native_touch";
type Initialize = unsafe extern "system" fn(UINT, DWORD) -> BOOL;
type Inject = unsafe extern "system" fn(UINT, *const POINTER_TOUCH_INFO) -> BOOL;

struct TouchApi {
    initialize: Initialize,
    inject: Inject,
}

fn api() -> Option<&'static TouchApi> {
    static API: OnceLock<Option<TouchApi>> = OnceLock::new();
    API.get_or_init(|| unsafe {
        let user32 = GetModuleHandleA(b"user32.dll\0".as_ptr().cast());
        if user32.is_null() {
            return None;
        }
        let initialize = GetProcAddress(user32, b"InitializeTouchInjection\0".as_ptr().cast());
        let inject = GetProcAddress(user32, b"InjectTouchInput\0".as_ptr().cast());
        if initialize.is_null() || inject.is_null() {
            return None;
        }
        Some(TouchApi {
            initialize: mem::transmute(initialize),
            inject: mem::transmute(inject),
        })
    })
    .as_ref()
}

pub(crate) fn advertise(additions: &mut serde_json::Map<String, serde_json::Value>) {
    if api().is_some() {
        additions.insert(CAPABILITY.into(), true.into());
    }
}

pub(crate) fn cancellation() -> PointerDeviceEvent {
    let mut event = PointerDeviceEvent::new();
    event.set_native_touch(NativeTouchContact {
        phase: Phase::CancelAll.into(),
        ..Default::default()
    });
    event
}

#[derive(Default)]
struct Contacts {
    owner: Option<i32>,
    points: BTreeMap<u32, POINT>,
    initialized: bool,
}

pub(crate) fn handle(contact: &NativeTouchContact, connection: i32) {
    static STATE: OnceLock<Mutex<Contacts>> = OnceLock::new();
    let Some(api) = api() else { return };
    let Ok(phase) = contact.phase.enum_value() else {
        return;
    };
    let mut state = STATE.get_or_init(Mutex::default).lock().unwrap();
    if state.owner.is_some_and(|id| id != connection) {
        return;
    }
    if phase == Phase::CancelAll {
        state.cancel(api);
        return;
    }
    let prior = state.points.get(&contact.id).copied();
    let (point, flags) = match phase {
        Phase::Down if prior.is_none() && state.points.len() < MAX_CONTACTS => {
            if !on_default_input_desktop() {
                return;
            }
            (
                POINT {
                    x: contact.x,
                    y: contact.y,
                },
                winuser::POINTER_FLAG_DOWN | CONTACT,
            )
        }
        Phase::Move if prior.is_some() => (
            POINT {
                x: contact.x,
                y: contact.y,
            },
            UPDATE,
        ),
        Phase::Up | Phase::Cancel => {
            let Some(prior) = prior else { return };
            let cancelled = if phase == Phase::Cancel {
                winuser::POINTER_FLAG_CANCELED
            } else {
                0
            };
            (prior, winuser::POINTER_FLAG_UP | cancelled)
        }
        _ => return,
    };
    if unsafe { winuser::MonitorFromPoint(point, winuser::MONITOR_DEFAULTTONULL) }.is_null() {
        if prior.is_some() {
            state.cancel(api);
        }
        return;
    }
    if !state.initialized {
        if unsafe { (api.initialize)(MAX_CONTACTS as UINT, winuser::TOUCH_FEEDBACK_NONE) } == FALSE
        {
            hbb_common::throttled_log!(
                Duration::from_secs(5),
                warn,
                "Could not initialize touch injection: {}",
                io::Error::last_os_error()
            );
            return;
        }
        state.initialized = true;
    }
    let mut frame = Vec::with_capacity(MAX_CONTACTS);
    for (&id, &point) in &state.points {
        if id != contact.id {
            frame.push(touch(id, point, UPDATE));
        }
    }
    frame.push(touch(contact.id, point, flags));
    if let Err(error) = inject(api, &frame) {
        hbb_common::throttled_log!(
            Duration::from_secs(5),
            warn,
            "Could not inject touch input: {error}"
        );
        state.cancel(api);
        return;
    }
    if phase == Phase::Up || phase == Phase::Cancel {
        state.points.remove(&contact.id);
    } else {
        state.points.insert(contact.id, point);
    }
    state.owner = (!state.points.is_empty()).then_some(connection);
}

const CONTACT: UINT = winuser::POINTER_FLAG_INRANGE | winuser::POINTER_FLAG_INCONTACT;
const UPDATE: UINT = winuser::POINTER_FLAG_UPDATE | CONTACT;

fn touch(id: u32, point: POINT, flags: UINT) -> POINTER_TOUCH_INFO {
    let mut touch = unsafe { mem::zeroed::<POINTER_TOUCH_INFO>() };
    touch.pointerInfo.pointerType = winuser::PT_TOUCH;
    touch.pointerInfo.pointerId = id;
    touch.pointerInfo.ptPixelLocation = point;
    touch.pointerInfo.pointerFlags = flags;
    touch
}

fn inject(api: &TouchApi, frame: &[POINTER_TOUCH_INFO]) -> io::Result<()> {
    if unsafe { (api.inject)(frame.len() as UINT, frame.as_ptr()) } != FALSE {
        return Ok(());
    }
    let error = io::Error::last_os_error();
    if error.raw_os_error() == Some(ERROR_NOT_READY as i32) {
        // Windows rejects injections in the same timestamp interval.
        std::thread::sleep(Duration::from_millis(1));
        if unsafe { (api.inject)(frame.len() as UINT, frame.as_ptr()) } != FALSE {
            return Ok(());
        }
        return Err(io::Error::last_os_error());
    }
    Err(error)
}

impl Contacts {
    fn cancel(&mut self, api: &TouchApi) {
        if !self.points.is_empty() {
            let flags = winuser::POINTER_FLAG_UP | winuser::POINTER_FLAG_CANCELED;
            let frame: Vec<_> = self
                .points
                .iter()
                .map(|(&id, &point)| touch(id, point, flags))
                .collect();
            if let Err(error) = inject(api, &frame) {
                hbb_common::throttled_log!(
                    Duration::from_secs(5),
                    warn,
                    "Could not cancel touch contacts: {error}"
                );
            }
        }
        self.points.clear();
        self.owner = None;
    }
}

pub(crate) fn on_default_input_desktop() -> bool {
    let mut name = [0u16; 32];
    let mut length = 0;
    unsafe {
        let desktop = winuser::OpenInputDesktop(0, FALSE, winuser::DESKTOP_READOBJECTS);
        if desktop.is_null() {
            return false;
        }
        let result = winuser::GetUserObjectInformationW(
            desktop.cast(),
            winuser::UOI_NAME as LONG,
            name.as_mut_ptr().cast(),
            mem::size_of_val(&name) as DWORD,
            &mut length,
        );
        winuser::CloseDesktop(desktop);
        result != FALSE
            && String::from_utf16_lossy(&name)
                .trim_end_matches('\0')
                .eq_ignore_ascii_case("Default")
    }
}
