ScriptName ZigExampleCaller

; Declared here, implemented by skse-plugin-zig-papyrus.dll as Global Native.
Int Function Sum(Int a, Int b) Global Native
Int Function Tick() Global Native
Float Function Scale(Float v, Float k) Global Native
Bool Function IsEven(Int n) Global Native

; Attached with the console command APS, e.g. "APS player ZigExampleCaller".
Event OnScriptLoad()
    Int total = Sum(2, 3)
    Int calls = Tick()
    Float scaled = Scale(1.5, 2.0)
    Bool even = IsEven(total)
    Debug.Trace("zig: sum=" + total + " tick=" + calls + " scale=" + scaled + " even=" + even)
EndEvent
