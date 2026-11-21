ScriptName ZigExampleCaller

; Declared here, implemented by skse-plugin-zig-papyrus.dll as Global Native.
Int Function Sum(Int a, Int b) Global Native
Int Function Tick() Global Native
Float Function Scale(Float v, Float k) Global Native
Bool Function IsEven(Int n) Global Native

; Select a reference in the console, then "APS ZigExampleCaller Run".
; OnInit runs when the instance is created; Run also exists so APS's
; optional second argument has a target. Each native logs its own result
; to the plugin log and the console, so Run only makes the calls.
Function Run()
    Int total = Sum(2, 3)
    Int calls = Tick()
    Float scaled = Scale(1.5, 2.0)
    Bool even = IsEven(total)
EndFunction

Event OnInit()
    Run()
EndEvent
