"""The sidebar: every profile with its status dot, tags and a select handler."""

def:pub ProfileList(
    profiles: list[ProfileOut], selected: str, on_select: any, on_new: any
) -> JsxElement {
    return <aside className="sidebar">
        <h1>CloakBrowser Manager</h1>
        <button className="primary" onClick={on_new}>+ New profile</button>
        <div>
            {[
                <div
                    key={p.id}
                    className={"row sel" if p.id == selected else "row"}
                    onClick={lambda { on_select(p.id); }}
                >
                    <span>
                        <span className={"dot on" if p.status == "running" else "dot"}></span>
                        {p.name}
                    </span>
                    <span>
                        {[<span key={t.tag} className="tag">{t.tag}</span> for t in p.tags]}
                    </span>
                </div>
                for p in profiles
            ]}
        </div>
    </aside>;
}
