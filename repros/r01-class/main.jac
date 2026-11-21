class P {
    has x: int = 0;
    def double -> int { return self.x * 2; }
}
with entry:__main__ { print(P(x=2).double()); }
