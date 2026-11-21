import hmac;
import from stdjac.bound { Secret }
import from stdjac.server { Auth, Rejected, Session, SignIn, SignInAction, SignInField }

obj TokenAuth(Auth) {
    has token: Secret = Secret(variable="AUTH_TOKEN");

    def configured -> str;

    def open;

    def matches(given: str) -> bool;

    def caller(headers: dict[str, str]) -> str | None;

    def asks(headers: dict[str, str]) -> SignIn;

    def answer(action: str, given: dict[str, str], client: str) -> Session;

    def leave(headers: dict[str, str]);
}
