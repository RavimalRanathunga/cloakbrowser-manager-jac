"""Types that cross between the server and the pages: the API's response shapes."""

obj TagOut {
    has tag: str,
        color: str = "";
}

obj ProfileOut {
    has id: str,
        name: str,
        fingerprint_seed: int,
        proxy: str = "",
        timezone: str = "",
        locale: str = "",
        screen_width: int = 1920,
        screen_height: int = 1080,
        gpu_family: str = "auto",
        humanize: bool = False,
        human_preset: str = "default",
        geoip: bool = True,
        clipboard_sync: bool = True,
        auto_launch: bool = False,
        color_scheme: str = "",
        launch_args: list[str] = [],
        extension_paths: list[str] = [],
        allow_3p_cookies: bool = True,
        search_engine: str = "google",
        capture_preview: bool = True,
        restore_session: bool = True,
        transparent_proxy: bool = False,
        portable_cookies: bool = False,
        notes: str = "",
        user_data_dir: str = "",
        created_at: str = "",
        updated_at: str = "",
        sort_order: int = 0,
        tags: list[TagOut] = [],
        status: str = "stopped",
        runtime_mode: str = "docker",
        viewer_mode: str = "vnc",
        vnc_ws_port: int | None = None,
        cdp_url: str = "";
}

obj ArtifactOut {
    has id: str,
        profile_id: str,
        name: str,
        size: int,
        kind: str,
        state: str,
        content_type: str = "",
        created_at: str = "",
        picker_name: str = "",
        container_path: str = "";
}

"""Every endpoint answers with a status the way the HTTP API did, and a detail."""
obj OkReply {
    has status: int = 200,
        detail: str = "";
}

obj ProfileReply {
    has status: int = 200,
        detail: str = "",
        profile: ProfileOut | None = None;
}

obj ProfilesReply {
    has status: int = 200,
        detail: str = "",
        profiles: list[ProfileOut] = [];
}

obj ArtifactReply {
    has status: int = 200,
        detail: str = "",
        artifact: ArtifactOut | None = None;
}

obj ArtifactsReply {
    has status: int = 200,
        detail: str = "",
        artifacts: list[ArtifactOut] = [];
}

obj FileReply {
    has status: int = 200,
        detail: str = "",
        name: str = "",
        data: bytes = b"";
}

obj LaunchReply {
    has status: int = 200,
        detail: str = "",
        profile_id: str = "",
        state: str = "running",
        runtime_mode: str = "docker",
        viewer_mode: str = "vnc",
        vnc_ws_port: int | None = None,
        display: str = "",
        cdp_url: str = "";
}

obj StatusOut {
    has status: int = 200,
        detail: str = "",
        running_count: int = 0,
        binary_version: str = "",
        license_tier: str = "none",
        profiles_total: int = 0,
        host_os: str = "linux",
        runtime_mode: str = "docker",
        viewer_mode: str = "vnc";
}

obj SettingsOut {
    has status: int = 200,
        detail: str = "",
        license_key_set: bool = False,
        license_key_masked: str = "",
        release_channel: str = "stable";
}

obj ConfigOut {
    has sidebar_width: str = "16rem";
}

obj AuthStatusOut {
    has auth_required: bool = False,
        authenticated: bool = False;
}
