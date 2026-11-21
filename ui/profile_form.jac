"""Create / edit a profile: the common fields, serialised to the JSON the server validates."""


def:pub ProfileForm(initial: ProfileOut | None, on_save: any, on_cancel: any) -> JsxElement {
    has name: str = initial.name if initial is not None else "";
    has proxy: str = initial.proxy if initial is not None and initial.proxy is not None else "";
    has timezone: str = initial.timezone
        if initial is not None and initial.timezone is not None
        else "";
    has locale: str = initial.locale if initial is not None and initial.locale is not None else "";
    has gpu: str = initial.gpu_family if initial is not None else "auto";
    has engine: str = initial.search_engine if initial is not None else "google";
    has humanize: bool = initial.humanize if initial is not None else False;
    has auto_launch: bool = initial.auto_launch if initial is not None else False;
    has notes: str = initial.notes if initial is not None and initial.notes is not None else "";
    has tags_text: str = ", ".join([t.tag for t in initial.tags]) if initial is not None else "";

    def jstr(text: str) -> str {
        t = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
        return '"' + t + '"';
    }

    def jopt(text: str) -> str {
        if text.strip() == "" {
            return "null";
        }
        return jstr(text.strip());
    }

    def jbool(flag: bool) -> str {
        return "true" if flag else "false";
    }

    def submit(e: any) {
        e.preventDefault();
        tag_items = [t.strip() for t in tags_text.split(",") if t.strip() != ""];
        tags_json = "[" + ", ".join(['{"tag": ' + jstr(t) + '}' for t in tag_items]) + "]";
        body = '{"name": ' + jstr(name.strip()) + ', "proxy": ' + jopt(proxy) + ', "timezone": ' + jopt(timezone) + ', "locale": ' + jopt(locale) + ', "gpu_family": ' + jstr(gpu) + ', "search_engine": ' + jstr(engine) + ', "humanize": ' + jbool(humanize) + ', "auto_launch": ' + jbool(auto_launch) + ', "notes": ' + jopt(notes) + ', "tags": ' + tags_json + '}';
        on_save(body);
    }

    return <form className="panel" onSubmit={submit}>
        <h2>{"Edit profile" if initial is not None else "New profile"}</h2>
        <label>Name</label>
        <input value={name} onInput={lambda (e: any) { name = e.target.value; }} />
        <label>Proxy (http://user:pass@host:port)</label>
        <input value={proxy} onInput={lambda (e: any) { proxy = e.target.value; }} />
        <label>Timezone</label>
        <input value={timezone} onInput={lambda (e: any) { timezone = e.target.value; }} />
        <label>Locale</label>
        <input value={locale} onInput={lambda (e: any) { locale = e.target.value; }} />
        <label>GPU family</label>
        <select value={gpu} onChange={lambda (e: any) { gpu = e.target.value; }}>
            <option value="auto">auto</option>
            <option value="nvidia">nvidia</option>
            <option value="intel">intel</option>
        </select>
        <label>Search engine</label>
        <select value={engine} onChange={lambda (e: any) { engine = e.target.value; }}>
            <option value="google">google</option>
            <option value="bing">bing</option>
            <option value="duckduckgo">duckduckgo</option>
            <option value="none">none</option>
        </select>
        <label><input
            type="checkbox"
            checked={humanize}
            onChange={lambda (e: any) { humanize = e.target.checked; }}
        /> Humanize input</label>
        <label><input
            type="checkbox"
            checked={auto_launch}
            onChange={lambda (e: any) { auto_launch = e.target.checked; }}
        /> Launch at startup</label>
        <label>Tags (comma separated)</label>
        <input value={tags_text} onInput={lambda (e: any) { tags_text = e.target.value; }} />
        <label>Notes</label>
        <textarea value={notes} onInput={lambda (e: any) { notes = e.target.value; }}></textarea>
        <div className="bar">
            <button type="submit" className="primary">Save</button>
            <button type="button" onClick={on_cancel}>Cancel</button>
        </div>
    </form>;
}
