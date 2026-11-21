import "./styles/app.css";

def:pub app(children: any) -> JsxElement {
    return <div className="app-root">{children}</div>;
}
