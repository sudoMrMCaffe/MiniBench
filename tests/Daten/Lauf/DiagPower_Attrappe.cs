public static class DiagPower {
    public static int Calls, Begins, Ends;
    public static bool Active;
    public static string State = "";
    public static uint SetThreadExecutionState(uint esFlags) { Calls++; return 0x80000000; }
    public static bool Begin(string reason) { Begins++; Active = true; State = "aktiv (Systemanforderung, Testattrappe)"; return true; }
    public static void End() { Ends++; Active = false; }
}
