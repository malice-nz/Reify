<h1 align="center"><img width="256" height="256" alt="8425128273" src="https://github.com/user-attachments/assets/ba99d81a-5e2d-4c83-9411-3f70b24f1da7" /><br/>Reify</h1>
<div align="center">Load and run RBXMs into your executor's environment</div><br>
<h1></h1>

```luau
local Reify  = loadstring(game:HttpGet('https://raw.githubusercontent.com/malice-nz/Reify/main/main.luau'))':3';
```

## What it is

Reify takes a `.rbxm` or `.rbxmx` file and rebuilds it as real Roblox instances inside your executor, then lets you run the scripts inside it. Point it at a model, get the tree back, require a module, parent a GUI, whatever you need.

It started as a modern rewrite of richie's rbxm-suite, with one big difference: everything it hands you is a real instance.

## Why real instances

Most loaders fake the tree with plain Lua tables. That is fine right up until something calls `:IsA`, `:WaitForChild`, or tries to parent the thing into your PlayerGui, and then the illusion falls apart. Reify builds actual instances with `Instance.new`, so all of that behaves the way you already expect it to.

The one thing Roblox will not let you do is set `.Source` on a script at runtime. Reify works around that by keeping each script's source off to the side and running it for you with `loadstring`. When it runs, `script` is the real instance and `require` resolves the rest of the modules in your model, so a folder full of modules that require each other loads exactly like it would in Studio.

## Examples

```luau
--# Library #--
local Module  = Reify.Load('Module.rbxm');
local Library = Reify.Require(Module);

Library.DoSomething();

--# GUI #--
local MainGui  = Reify.Load('GUI.rbxm');
MainGui.Parent  = LocalPlayer.PlayerGui
```

You do not have to give it a file path either. If you already have the raw model bytes (from `readfile`, an HTTP download, or anything else) you can pass those straight to `Reify.Load`.

## API

**`Reify.Load(pathOrData)`**

Reads a `.rbxm` or `.rbxmx` and returns the root instance. Takes a file path or the raw model string. If the file has more than one instance at the top level, they get wrapped in a Folder called `ReifyRoot`.

**`Reify.Require(instance)`**

Finds the head ModuleScript and runs it, returning whatever the module returns. The head is the instance itself if it is a module, otherwise a child named `init` or `main` or the same name as the folder, otherwise the first module it can find. Results are cached, just like a normal require.

**`Reify.Run(instance)`**

Runs every Script and LocalScript under the instance, each in its own thread. Returns how many it started.

**`Reify.GetSource(instance)`**

Hands back the stored source of a script Reify loaded, or nil if it does not have one.

## Notes

Reify reads string, bool, and shared string properties. That is everything a script or module needs. Richer properties like positions, colors, and object references are not applied yet, so a loaded GUI will have all the right instances in the right places but not their visual properties. That may change down the line.

Older LZ4 models decompress everywhere with the built in decoder. Newer ZSTD models go through EncodingService when your executor exposes it.

Scripts run through Reify's own loader rather than the Roblox script scheduler, since the engine will not run a script whose source was injected after the fact.

## Credits

Made by malice, inspired by richie's rbxm-suite.
