
#### <img width="24" height="24" alt="8425128273" src="https://github.com/user-attachments/assets/ba99d81a-5e2d-4c83-9411-3f70b24f1da7" /> Reify

*Load and run RBXMs into your executor's environment*

Reify takes a `.rbxm` or `.rbxmx` file and rebuilds it as real Roblox instances inside your executor, then lets you run the scripts inside it.

```luau
local Reify   = loadstring(game:HttpGet 'https://raw.githubusercontent.com/malice-nz/Reify/main/main.luau')':3';

--# Library #--
local Module  = Reify.Load('Module.rbxm');
local Library = Reify.Require(Module);

Library.DoSomething();

--# GUI #--
local MainGui  = Reify.Load('GUI.rbxm');
MainGui.Parent  = LocalPlayer.PlayerGui
```

<div align="right">Made by <a href="https://malice.nz">malice</a>, inspired by richie's rbxm-suite</div>
