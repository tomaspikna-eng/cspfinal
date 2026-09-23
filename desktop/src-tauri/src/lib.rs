use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tauri::{
    menu::{CheckMenuItemBuilder, MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    Manager,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};

const CSP_URL: &str = "https://connectsportspro.com";
const DESKTOP_VERSION: &str = "1.1.0";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DesktopSettings {
    start_maximized: bool,
    zoom: f64,
}

impl Default for DesktopSettings {
    fn default() -> Self {
        Self {
            start_maximized: false,
            zoom: 1.0,
        }
    }
}

fn settings_path(app: &tauri::AppHandle) -> Option<PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|dir| dir.join("desktop-settings.json"))
}

fn load_settings(app: &tauri::AppHandle) -> DesktopSettings {
    let Some(path) = settings_path(app) else {
        return DesktopSettings::default();
    };

    fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str::<DesktopSettings>(&raw).ok())
        .unwrap_or_default()
}

fn save_settings(app: &tauri::AppHandle, settings: &DesktopSettings) {
    let Some(path) = settings_path(app) else {
        return;
    };

    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    if let Ok(raw) = serde_json::to_string_pretty(settings) {
        let _ = fs::write(path, raw);
    }
}

fn apply_zoom(app: &tauri::AppHandle, zoom: f64) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_zoom(zoom);
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .setup(|app| {
            let handle = app.handle().clone();
            let settings = load_settings(&handle);
            let settings_state = Arc::new(Mutex::new(settings.clone()));

            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_zoom(settings.zoom);
                if settings.start_maximized {
                    let _ = window.maximize();
                }
            }

            let autostart_enabled = app.autolaunch().is_enabled().unwrap_or(false);

            let autostart_item =
                CheckMenuItemBuilder::with_id("autostart", "Spúšťať po štarte Windows")
                    .checked(autostart_enabled)
                    .build(app)?;

            let start_maximized_item =
                CheckMenuItemBuilder::with_id("start_maximized", "Spustiť maximalizované")
                    .checked(settings.start_maximized)
                    .build(app)?;

            let reload_item = MenuItemBuilder::with_id("reload", "Obnoviť CSP")
                .accelerator("Ctrl+R")
                .build(app)?;

            let fullscreen_item = MenuItemBuilder::with_id("fullscreen", "Celá obrazovka")
                .accelerator("F11")
                .build(app)?;

            let notifications_item =
                MenuItemBuilder::with_id("notifications_status", "Notifikácie – pripravujeme")
                    .enabled(false)
                    .build(app)?;

            let updates_item =
                MenuItemBuilder::with_id("updates_status", "Automatické aktualizácie – pripravujeme")
                    .enabled(false)
                    .build(app)?;

            let version_item = MenuItemBuilder::with_id(
                "version",
                format!("Connect Sports Pro Desktop v{DESKTOP_VERSION}"),
            )
            .enabled(false)
            .build(app)?;

            let application_menu = SubmenuBuilder::new(app, "Aplikácia")
                .item(&autostart_item)
                .item(&start_maximized_item)
                .separator()
                .item(&reload_item)
                .separator()
                .text("quit", "Ukončiť Connect Sports Pro")
                .build()?;

            let display_menu = SubmenuBuilder::new(app, "Zobrazenie")
                .text("zoom_80", "Zoom 80 %")
                .text("zoom_90", "Zoom 90 %")
                .text("zoom_100", "Zoom 100 %")
                .text("zoom_110", "Zoom 110 %")
                .text("zoom_125", "Zoom 125 %")
                .text("zoom_150", "Zoom 150 %")
                .separator()
                .item(&fullscreen_item)
                .build()?;

            let tools_menu = SubmenuBuilder::new(app, "Nástroje")
                .text("clear_cache", "Vymazať cache a odhlásiť")
                .text("open_web", "Otvoriť webovú verziu")
                .separator()
                .item(&notifications_item)
                .item(&updates_item)
                .build()?;

            let help_menu = SubmenuBuilder::new(app, "Pomoc")
                .item(&version_item)
                .separator()
                .text("csp_web", "connectsportspro.com")
                .build()?;

            let menu = MenuBuilder::new(app)
                .item(&application_menu)
                .item(&display_menu)
                .item(&tools_menu)
                .item(&help_menu)
                .build()?;

            app.set_menu(menu)?;

            let autostart_item_for_events = autostart_item.clone();
            let start_maximized_for_events = start_maximized_item.clone();
            let settings_for_events = settings_state.clone();

            app.on_menu_event(move |app_handle, event| {
                match event.id().as_ref() {
                    "autostart" => {
                        let manager = app_handle.autolaunch();
                        let currently_enabled = manager.is_enabled().unwrap_or(false);
                        let desired = !currently_enabled;

                        let result = if desired {
                            manager.enable()
                        } else {
                            manager.disable()
                        };

                        if result.is_ok() {
                            let _ = autostart_item_for_events.set_checked(desired);
                        } else {
                            let _ = autostart_item_for_events.set_checked(currently_enabled);
                        }
                    }
                    "start_maximized" => {
                        if let Ok(mut settings) = settings_for_events.lock() {
                            settings.start_maximized = !settings.start_maximized;
                            let _ =
                                start_maximized_for_events.set_checked(settings.start_maximized);
                            save_settings(app_handle, &settings);
                        }
                    }
                    "reload" => {
                        if let Some(window) = app_handle.get_webview_window("main") {
                            let _ = window.reload();
                        }
                    }
                    "fullscreen" => {
                        if let Some(window) = app_handle.get_webview_window("main") {
                            let fullscreen = window.is_fullscreen().unwrap_or(false);
                            let _ = window.set_fullscreen(!fullscreen);
                        }
                    }
                    "zoom_80" | "zoom_90" | "zoom_100" | "zoom_110" | "zoom_125"
                    | "zoom_150" => {
                        let zoom = match event.id().as_ref() {
                            "zoom_80" => 0.80,
                            "zoom_90" => 0.90,
                            "zoom_110" => 1.10,
                            "zoom_125" => 1.25,
                            "zoom_150" => 1.50,
                            _ => 1.00,
                        };

                        apply_zoom(app_handle, zoom);

                        if let Ok(mut settings) = settings_for_events.lock() {
                            settings.zoom = zoom;
                            save_settings(app_handle, &settings);
                        }
                    }
                    "clear_cache" => {
                        if let Some(window) = app_handle.get_webview_window("main") {
                            let _ = window.clear_all_browsing_data();
                            if let Ok(url) = CSP_URL.parse() {
                                let _ = window.navigate(url);
                            }
                        }
                    }
                    "open_web" | "csp_web" => {
                        let _ = open::that(CSP_URL);
                    }
                    "quit" => {
                        app_handle.exit(0);
                    }
                    _ => {}
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Connect Sports Pro");
}
