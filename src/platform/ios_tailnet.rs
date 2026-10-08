//! Only explicitly selected services enter tsnet. The loopback listeners are
//! owned by the iOS bridge; no global VPN, proxy setting or server rewrite is used.
use base::config::keys;
use hbb_common::{bail, config::Config, socket_client, tcp::FramedStream, ResultType, Stream};
use reqwest::{redirect::Policy, Client, Method, Proxy, Response};
use std::{
    ffi::CString,
    os::raw::{c_char, c_int},
    time::Duration,
};
use url::Url;

extern "C" {
    fn rd_tailnet_port(role: c_int, target: *const c_char) -> c_int;
}

pub fn enabled() -> bool {
    Config::get_option(keys::OPTION_IOS_TAILNET_ENABLED) == "Y"
}

pub fn id_enabled() -> bool {
    enabled() && Config::get_option(keys::OPTION_IOS_TAILNET_ID) == "Y"
}

pub fn routes_api(target: &str) -> bool {
    if !enabled() || Config::get_option(keys::OPTION_IOS_TAILNET_API) == "N" {
        return false;
    }
    let configured = Config::get_option(keys::OPTION_API_SERVER);
    matches!((Url::parse(target), Url::parse(&configured)), (Ok(a), Ok(b))
        if a.origin() == b.origin() && matches!(a.scheme(), "http" | "https"))
}

fn port(role: i32, target: &str) -> ResultType<u16> {
    let target = CString::new(target)?;
    // Go owns these synchronized values; the C string lives through the call.
    let port = unsafe { rd_tailnet_port(role, target.as_ptr()) };
    if port < 1 || port > u16::MAX as i32 {
        bail!("Tailscale is disconnected or its server configuration changed. Connect Tailscale and retry.");
    }
    Ok(port as u16)
}

pub fn http_client(target: &str) -> ResultType<Client> {
    let url = Url::parse(target)?;
    let proxy = Proxy::all(format!(
        "http://127.0.0.1:{}",
        port(0, &url.origin().ascii_serialization())?
    ))?;
    // Do not use the legacy certificate fallback or follow redirects out of the allowlist.
    Ok(Client::builder()
        .no_proxy()
        .proxy(proxy)
        .use_rustls_tls()
        .redirect(Policy::none())
        .timeout(Duration::from_secs(30))
        .build()?)
}

pub async fn request(
    target: &str,
    method: &str,
    body: Option<String>,
    headers: impl IntoIterator<Item = (String, String)>,
) -> ResultType<Response> {
    let (client, target) = match http_client(target) {
        Ok(client) => (client, target.to_owned()),
        Err(error) => match alternate(keys::OPTION_IOS_TAILNET_API_ALTERNATE) {
            Some(alternate) => {
                let mut url = Url::parse(&alternate)?;
                if !matches!(url.scheme(), "http" | "https")
                    || url.host_str().is_none()
                    || !url.username().is_empty()
                    || url.password().is_some()
                    || url.query().is_some()
                    || url.fragment().is_some()
                {
                    bail!("Invalid alternate API Server");
                }
                let original = Url::parse(target)?;
                let base = Url::parse(&Config::get_option(keys::OPTION_API_SERVER))?;
                let path = original
                    .path()
                    .strip_prefix(base.path().trim_end_matches('/'))
                    .ok_or_else(|| {
                        hbb_common::anyhow::anyhow!("API path is outside the configured server")
                    })?;
                url.set_path(&format!("{}{}", url.path().trim_end_matches('/'), path));
                url.set_query(original.query());
                (
                    Client::builder()
                        .no_proxy()
                        .use_rustls_tls()
                        .redirect(Policy::none())
                        .timeout(Duration::from_secs(30))
                        .build()?,
                    url.to_string(),
                )
            }
            None => return Err(error),
        },
    };
    let mut request = client.request(Method::from_bytes(method.as_bytes())?, target);
    for (name, value) in headers {
        request = request.header(name, value);
    }
    if let Some(body) = body {
        request = request.body(body);
    }
    Ok(request.send().await?)
}

fn alternate(key: &str) -> Option<String> {
    if Config::get_option(keys::OPTION_IOS_TAILNET_FALLBACK) != "alternate" {
        return None;
    }
    let value = Config::get_option(key);
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

async fn connect(target: String, timeout: u64, role: i32, option: &str) -> ResultType<Stream> {
    if !enabled() || Config::get_option(option) != "Y" {
        return socket_client::connect_tcp(target, timeout).await;
    }
    let port = match port(role, &target) {
        Ok(port) => port,
        Err(error) => {
            let (key, configured, default_port) = if role == 2 {
                (
                    keys::OPTION_IOS_TAILNET_RELAY_ALTERNATE,
                    keys::OPTION_RELAY_SERVER,
                    21117,
                )
            } else {
                (
                    keys::OPTION_IOS_TAILNET_ID_ALTERNATE,
                    keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
                    21116,
                )
            };
            let mut expected =
                socket_client::check_port(Config::get_option(configured), default_port);
            if role == 3 {
                expected = socket_client::increase_port(expected, -1);
            }
            if expected == target {
                if let Some(address) = alternate(key) {
                    let mut address = socket_client::check_port(address, default_port);
                    if role == 3 {
                        address = socket_client::increase_port(address, -1);
                    }
                    return socket_client::connect_tcp(address, timeout).await;
                }
            }
            return Err(error);
        }
    };
    // Bypass any user-configured system proxy for the process-local hop only.
    Ok(Stream::Tcp(
        FramedStream::new(format!("127.0.0.1:{port}"), None, timeout).await?,
    ))
}

pub async fn connect_id(target: impl ToString, timeout: u64) -> ResultType<Stream> {
    connect(target.to_string(), timeout, 1, keys::OPTION_IOS_TAILNET_ID).await
}

pub async fn connect_relay(target: impl ToString, timeout: u64) -> ResultType<Stream> {
    connect(
        target.to_string(),
        timeout,
        2,
        keys::OPTION_IOS_TAILNET_RELAY,
    )
    .await
}

pub async fn connect_online(target: impl ToString, timeout: u64) -> ResultType<Stream> {
    connect(target.to_string(), timeout, 3, keys::OPTION_IOS_TAILNET_ID).await
}
