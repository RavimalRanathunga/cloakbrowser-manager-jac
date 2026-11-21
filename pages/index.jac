import from "@jac/runtime" { RemoteRejected, sign_in }

def:pub page -> JsxPage {
    has profiles: list[ProfileOut] = [];
    has selected: str = "";
    has mode: str = "view";
    has error: str = "";
    has locked: bool = False;
    has files: list[ArtifactOut] = [];
    has license_masked: str = "";
    has channel: str = "stable";
    has key_draft: str = "";
    has summary: str = "";

    async def refresh {
        try {
            r: ProfilesReply = await list_profiles();
            profiles = r.profiles;
            locked = False;
            error = "";
            st: StatusOut = await system_status();
            summary = str(st.profiles_total) + " profiles, " + str(st.running_count) + " running";
        } except RemoteRejected as e {
            locked = True;
            error = e.detail;
        }
    }

    async def load_files(pid: str) {
        fr: ArtifactsReply = await list_files(pid);
        files = fr.artifacts;
    }

    async def select(pid: str) {
        selected = pid;
        mode = "view";
        await load_files(pid);
    }

    async def login {
        if await sign_in() {
            await refresh();
        }
    }

    async def save(body: str) {
        if mode == "new" {
            r: ProfileReply = await create_profile(body);
            if r.status != 201 {
                error = r.detail;
                return;
            }
            error = "";
            await refresh();
            if r.profile is not None {
                await select(r.profile.id);
            }
        } else {
            r: ProfileReply = await update_profile(selected, body);
            if r.status != 200 {
                error = r.detail;
                return;
            }
            error = "";
            mode = "view";
            await refresh();
        }
    }

    async def launch {
        l: LaunchReply = await launch_profile(selected);
        error = l.detail if l.status != 200 else "";
        await refresh();
    }

    async def stop {
        o: OkReply = await stop_profile(selected);
        error = o.detail if o.status != 200 else "";
        await refresh();
    }

    async def remove_selected {
        o: OkReply = await delete_profile(selected);
        selected = "";
        await refresh();
    }

    async def duplicate {
        r: ProfileReply = await duplicate_profile(selected);
        await refresh();
    }

    async def reset {
        r: ProfileReply = await reset_profile(selected);
        await refresh();
    }

    async def drop_file(fid: str) {
        o: OkReply = await delete_file(selected, fid);
        await load_files(selected);
    }

    async def load_settings {
        s: SettingsOut = await get_settings();
        license_masked = s.license_key_masked if s.license_key_masked is not None else "";
        channel = s.release_channel;
        mode = "settings";
    }

    async def save_settings {
        safe_key = key_draft.strip().replace("\\", "\\\\").replace('"', '\\"');
        body = '{"license_key": "' + safe_key + '", "release_channel": "' + channel + '"}';
        st: StatusOut = await put_settings(body);
        error = st.detail if st.status != 200 else "";
        key_draft = "";
        await load_settings();
    }

    async can with entry {
        await refresh();
    }

    current = [p for p in profiles if p.id == selected];

    if locked {
        return <div className="main">
            <h1>CloakBrowser Manager</h1>
            <p className="dim">This Manager needs an access token.</p>
            <button className="primary" onClick={login}>Sign in</button>
            <p className="err">{error}</p>
        </div>;
    }

    return <div className="app">
        <ProfileList
            profiles={profiles}
            selected={selected}
            on_select={select}
            on_new={lambda { mode = "new"; }}
        />
        <main className="main">
            <div className="bar">
                <span className="dim">{summary}</span>
                <button onClick={load_settings}>Settings</button>
            </div>
            <p className="err">{error}</p>
            {<ProfileForm
                key="new"
                initial={None}
                on_save={save}
                on_cancel={lambda { mode = "view"; }}
            />
                if mode == "new"
                else <span></span>}
            {<section className="panel">
                <h2>License</h2>
                <p className="dim">Current key: {license_masked
                    if license_masked != ""
                    else "none"}</p>
                <label>License key</label>
                <input
                    value={key_draft}
                    onInput={lambda (e: any) { key_draft = e.target.value; }}
                />
                <label>Release channel</label>
                <select value={channel} onChange={lambda (e: any) { channel = e.target.value; }}>
                    <option value="stable">stable</option>
                    <option value="preview">preview</option>
                </select>
                <div className="bar">
                    <button className="primary" onClick={save_settings}>Save</button>
                </div>
            </section>
                if mode == "settings"
                else <span></span>}
            {[
                <section key={p.id} className="panel">
                    <h2>{p.name} <span className="dim">{p.status}</span></h2>
                    <p
                        className="dim"
                    >seed {p.fingerprint_seed} · {p.screen_width}x{p.screen_height} · gpu {p.gpu_family} · {p.proxy
                        if p.proxy != ""
                        else "no proxy"}</p>
                    <div className="bar">
                        {<button className="primary" onClick={launch}>Launch</button>
                            if p.status != "running"
                            else <button onClick={stop}>Stop</button>}
                        <button onClick={lambda { mode = "edit"; }}>Edit</button>
                        <button onClick={duplicate}>Duplicate</button>
                        <button onClick={reset}>Reset</button>
                        <button className="danger" onClick={remove_selected}>Delete</button>
                    </div>
                    {<ProfileForm
                        key={p.id}
                        initial={p}
                        on_save={save}
                        on_cancel={lambda { mode = "view"; }}
                    />
                        if mode == "edit"
                        else <span></span>}
                    <h3>Files</h3>
                    <ul>
                        {[
                            <li key={f.id}>{f.name} <span
                                className="dim"
                            >({f.size} bytes)</span> <button
                                onClick={lambda { drop_file(f.id) }}
                            >Remove</button></li>
                            for f in files
                        ]}
                    </ul>
                </section>
                for p in current
            ]}
        </main>
    </div>;
}
