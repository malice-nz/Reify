--!optimize 2

--# Reify
--? Modern version of richie's rbxm-suite
--? Run RBXMs in your executor's environment

--* malice.nz

local Reify	= {}

local getgenv	= getgenv or function() return {} end;
local cloneref	= cloneref or function(v) return v end;
local readfile	= readfile;
local setthreadidentity	= setthreadidentity or function() end;

--# Splash Logo #--
local RealConsole	= loadstring(game:HttpGet('https://raw.githubusercontent.com/malice-nz/RealConsole/main/main.luau'))':3';
local MonoFont		= Font.new('rbxasset://fonts/families/RobotoMono.json');
do
	if(not(getgenv()['____REIFY_SPLASH'])) then
		RealConsole:Banner('rbxassetid://8425128273', 'Reify')
		RealConsole:Output('https://github.com/malice-nz/Reify', MonoFont)
		RealConsole:Output('https://malice.nz', MonoFont)
	end
	getgenv()['____REIFY_SPLASH'] = true;
end;

--# Reader #--
local function BinaryReader(Data)
	local Buffer	= buffer.fromstring(Data);
	local Stream	= { 
		Buffer	= Buffer,
		Offset	= 0,
		Length	= buffer.len(Buffer)
	};

	function Stream:U8() local V = buffer.readu8(self.Buffer, self.Offset); self.Offset += 1; return V end
	function Stream:U16() local V = buffer.readu16(self.Buffer, self.Offset); self.Offset += 2; return V end
	function Stream:U32() local V = buffer.readu32(self.Buffer, self.Offset); self.Offset += 4; return V end
	function Stream:I32() local V = buffer.readi32(self.Buffer, self.Offset); self.Offset += 4; return V end
	function Stream:Bytes(N) local V = buffer.readstring(self.Buffer, self.Offset, N); self.Offset += N; return V end
	function Stream:String() local N = self:U32(); return self:Bytes(N) end
	function Stream:Skip(N) self.Offset += N end
	function Stream:Remaining() return self.Length - self.Offset end
	return Stream
end;

--# Services #--
local EncodingService	= cloneref(game:GetService('EncodingService'));

--# Block Decompression #--
local Lz4Decompress		= lz4decompress or (crypt and crypt.lz4decompress) or function(Compressed, Size)
	--? Your executor fucking sucks

	local In		= buffer.fromstring(Compressed);
	local InLength	= buffer.len(In);
	local Out		= buffer.create(Size);
	local IPosition, OPosition = 0, 0;

	while(IPosition < InLength) do
		local Token	= buffer.readu8(In, IPosition); IPosition += 1;

		--$ Literals $--
		local LiteralLength	= bit32.rshift(Token, 4);
		if(LiteralLength == 15) then
			while(true) do
				local Byte	= buffer.readu8(In, IPosition); IPosition += 1;
				LiteralLength += Byte;
				if(Byte ~= 255) then break end;
			end;
		end;

		for _ = 1, LiteralLength do
			buffer.writeu8(Out, OPosition, buffer.readu8(In, IPosition))
			IPosition += 1; OPosition += 1
		end
		if(IPosition >= InLength) then break end

		--$ Match $--
		local Offset = buffer.readu8(In, IPosition) + buffer.readu8(In, IPosition + 1) * 256;
		IPosition	+= 2;
		local MatchLen = bit32.band(Token, 15)
		if MatchLen == 15 then
			while true do
				local B = buffer.readu8(In, IPosition); IPos += 1
				MatchLen += B
				if B ~= 255 then break end
			end
		end
		MatchLen	+= 4;
		local MatchPos = OPosition - Offset
		for _ = 1, MatchLen do
			buffer.writeu8(Out, OPosition, buffer.readu8(Out, MatchPos))
			OPos += 1; MatchPos += 1
		end;
	end;

	return(buffer.tostring(Out));
end;

--# Integer Decoding #--
local function ReadIU32(Reader, Count)
	local Raw		= buffer.fromstring(Reader:Bytes(Count * 4));
	local Result	= table.create(Count);
	for I = 0, Count - 1 do
		local Byte0 = buffer.readu8(Raw, 0 * Count + I);
		local Byte1 = buffer.readu8(Raw, 1 * Count + I);
		local Byte2 = buffer.readu8(Raw, 2 * Count + I);
		local Byte3 = buffer.readu8(Raw, 3 * Count + I);
		Result[I + 1] = (Byte0 * 0x1000000 + Byte1 * 0x10000 + Byte2 * 0x100 + Byte3);
	end
	return(Result)
end;

local function Zigzag(N)
	local Shifted = bit32.rshift(N, 1)
	if(bit32.band(N, 1) == 1 )then return -(Shifted + 1) end
	return(Shifted)
end;

local function ReadReferents(Reader, Count)
	local Raw			= ReadIU32(Reader, Count);
	local Result		= table.create(Count);
	local Accumulator	= 0;
	for i = 1, Count do
		Accumulator += Zigzag(Raw[i])
		Result[i] = Accumulator
	end;
	return(Result);
end;

--# Nodes #--
local function NewNode(ClassName)
	return { 
		ClassName	= ClassName, 
		Name		= ClassName, 
		Source		= nil, 
		Parent		= nil, 

		_children	= {}, 
		_properties	= {} 
	};
end;

local function SetProp(Node, Name, Value)
	Node._properties[Name] = Value;
	if(Name == 'Name') then Node.Name = Value;
	elseif(Name == 'Source') then Node.Source = Value end;
end;

--# Binary Parser #--
local PROP_STRING		= 0x01;
local PROP_BOOL			= 0x02;
local PROP_SHAREDSTRING	= 0x1C;

local function ParseBinary(Data)
	local Reader	= BinaryReader(Data)

	Reader:Skip(8);	--? '<roblox!'
	Reader:Skip(6);	--? Signature
	Reader:U16();	--? Version
	Reader:U32();	--? Class Count
	Reader:U32();	--? Instance Count
	Reader:Skip(8);	--? Reserved

	local Instances			= {};
	local ClassReferences	= {};
	local SharedStrings		= {};

	while(Reader:Remaining() >= 16) do
		local Name				= Reader:Bytes(4);
		local CompressedSize	= Reader:U32();
		local DecompressedSize	= Reader:U32();
		Reader:U32();	--? Reserved

		local ChunkData;
		if(CompressedSize == 0) then
			ChunkData	= Reader:Bytes(DecompressedSize);
		else
			local Compressed	= Reader:Bytes(CompressedSize);
			if(Compressed:byte(1) == 0x28 and Compressed:byte(2) == 0xB5) then
				ChunkData	= buffer.tostring(EncodingService:DecompressBuffer(Compressed, Enum.CompressionAlgorithm.Zstd));
			else
				ChunkData	= Lz4Decompress(Compressed, DecompressedSize);
			end;
		end;

		local Chunk = BinaryReader(ChunkData);

		if(Name == 'INST') then
			local ClassIndex	= Chunk:U32();
			local ClassName		= Chunk:String();
			local IsService		= Chunk:U8() ~= 0;
			local Count			= Chunk:U32();
			local References	= ReadReferents(Chunk, Count);

			if(IsService) then Chunk:Skip(Count) end;
			ClassReferences[ClassIndex] = { ClassName = ClassName, References = References };
			for _, Reference in References do
				Instances[Reference] = NewNode(ClassName);
			end;

		elseif(Name == 'SSTR') then
			Chunk:U32()
			local Count = Chunk:U32()
			for i = 1, Count do
				Chunk:Skip(16)
				SharedStrings[i - 1] = Chunk:String()
			end

		elseif(Name == 'PROP') then
			local ClassIndex		= Chunk:U32();
			local PropertyName		= Chunk:String();
			local PropertyType		= Chunk:U8();

			local Class	= ClassReferences[ClassIndex]
			if(Class) then
				local References	= Class.References
				if(PropertyType == PROP_STRING) then
					for _, Reference in References do
						local Value		= Chunk:String();
						local Instance	= Instances[Reference];
						if(Instance) then SetProp(Instance, PropertyName, Value) end
					end
				elseif(PropertyType == PROP_BOOL) then
					for _, Reference in References do
						local Value		= Chunk:U8() ~= 0;
						local Instance	= Instances[Reference];
						if(Instance) then SetProp(Instance, PropertyName, Value) end
					end
				elseif(PropertyType == PROP_SHAREDSTRING) then
					local Indices	= ReadIU32(Chunk, #References)
					for i, Reference in References do
						local Instance	= Instances[Reference]
						if(Instance) then SetProp(Instance, PropertyName, SharedStrings[Indices[i]]) end
					end
				end
				--? Unknown Property
			end

		elseif(Name == 'PRNT') then
			Chunk:U8();
			local Count		= Chunk:U32();
			local Children	= ReadReferents(Chunk, Count);
			local Parents	= ReadReferents(Chunk, Count);

			for i = 1, Count do
				local Child				= Instances[Children[i]];
				local ParentReference	= Parents[i];
				if(Child) then
					if(ParentReference == -1) then
						Child.Parent	= nil
					else
						local Parent	= Instances[ParentReference];
						if(Parent) then
							Child.Parent	= Parent;
							table.insert(Parent._children, Child);
						end;
					end;
				end;
			end;
		elseif(Name == 'END\0') then
			break;
		end;
	end;

	local Roots	= {};
	for _, Instance in Instances do
		if Instance.Parent == nil then Roots[#Roots + 1] = Instance end;
	end;
	return(Roots);
end;

--# XML Parser #--
local function Sanitise(Text)
	return (Text:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', '\''):gsub('&amp;', '&'));
end;

local function ParseXML(Data)
	local Position	= 1;
	local function ParseItems(StopPattern)
		local Items	= {};

		while(true) do
			local S, E, Class	= Data:find('<Item%s+class="([^"]+)"[^>]*>', Position);
			if(not S) then break end;
			if(StopPattern) then
				local CloseS = Data:find(StopPattern, Position);
				if CloseS and CloseS < S then break end;
			end;

			Position = (E + 1);

			local Instance			= NewNode(Class);
			local PropertiesEnd		= Data:find('</Properties>', Position) or #Data :: number;
			local PropertiesBlock	= Data:sub(Position, PropertiesEnd);
			local NameValue			= PropertiesBlock:match('<string name="Name">(.-)</string>');

			if(NameValue) then SetProp(Instance, 'Name', Sanitise(NameValue)) end;

			local SourceVal	= PropertiesBlock:match('<ProtectedString name="Source"><!%[CDATA%[(.-)%]%]></ProtectedString>')
				or PropertiesBlock:match('<ProtectedString name="Source">(.-)</ProtectedString>')
				or PropertiesBlock:match('<string name="Source"><!%[CDATA%[(.-)%]%]></string>');

			if(SourceVal) then SetProp(Instance, 'Source', Sanitise(SourceVal)) end;

			Position = (PropertiesEnd + 1);

			for _, Child in ParseItems('</Item>') do
				Child.Parent	= Instance;
				table.insert(Instance._children, Child);
			end;

			local CloseS, CloseE	= Data:find('</Item>', Position)

			if CloseS then Position = CloseE + 1 end;

			Items[#Items + 1]	= Instance;
		end
		return(Items)
	end
	return(ParseItems(nil))
end;

--# Realise #--
local ScriptSources		= setmetatable({}, { __mode = 'k' });

local function Realise(Node, Parent)
	local Creatable, Object = pcall(Instance.new, Node.ClassName)
	if(not Creatable or typeof(Object) ~= 'Instance') then
		Object	= Instance.new('Folder')
	end;

	local IsScript	= table.find({ 'ModuleScript', 'LocalScript', 'Script' }, Node.ClassName);
	for Key, Value in Node._properties do
		if(Key == 'Source' and IsScript) then
			ScriptSources[Object]	= Value;	--? .Source
		else
			pcall(function() Object[Key]	= Value; end);
		end;
	end;

	if(IsScript and Node.Source and ScriptSources[Object] == nil) then
		ScriptSources[Object] = Node.Source;
	end;

	for _, Child in Node._children do
		Realise(Child, Object);
	end;

	if(Parent) then Object.Parent	= Parent end;
	return(Object);
end;

--# Load #--
local function Resolve(Data)
	if(type(Data) ~= 'string') then return(RealConsole:Error('Expected a file path or data string!', MonoFont)) end
	if(Data:sub(1, 7) == '<roblox') then return Data end
	if(not readfile) then return(RealConsole:Error('Your executor doesnt support readfile, sorry!', MonoFont)) end
	return readfile(Data)
end;

function Reify.Load(Data)
	local Data	= Resolve(Data);
	local Roots;

	if(Data:sub(1, 8) == '<roblox!') then
		Roots	= ParseBinary(Data);
	elseif(Data:sub(1, 7) == '<roblox') then
		Roots	= ParseXML(Data);
	else
		return(RealConsole:Error('Bad magic, provided data is not a RBXM.', MonoFont))
	end;

	local RealRoots	= {}
	for _, Node in Roots do RealRoots[#RealRoots + 1]	= Realise(Node, nil); end;
	if(#RealRoots == 1) then return RealRoots[1] end;

	local Container	= Instance.new('Folder');
	Container.Name	= `{tick()}_RBXContainer`;

	for _, Root in RealRoots do Root.Parent	= Container end;
	return(Container);
end;


--# Module Building #--
local function IsModule(Inst) return(typeof(Inst) == 'Instance' and Inst:IsA('ModuleScript')) end;
local function FindModule(Root)
	if(IsModule(Root)) then return(Root) end;
	local ContainerName	= Root.Name:lower();
	for _, Child in Root:GetChildren() do
		if(IsModule(Child)) then
			if(string.lower(Child.Name) == ContainerName) then return(Child) end;
		end;
	end;

	local Queue	= Root:GetChildren();
	local Head	= 1;

	while(Head <= #Queue) do
		local Node	= Queue[Head]; Head += 1;
		if(IsModule(Node)) then return(Node) end;
		for _, C in Node:GetChildren() do Queue[#Queue + 1] = C end;
	end;

	return(nil);
end;

local RequireCache	= setmetatable({}, { __mode = 'k' });
local RunModule;

local function BuildRequire(Owner)
	return function(Target:ModuleScript)
		if(typeof(Target) == 'Instance') then
			if(ScriptSources[Target] ~= nil) then return(RunModule(Target)) end;
			if(Target:IsA('ModuleScript')) then
				local Loadable, Response	= pcall(require, Target);
				if(Loadable) then return(Response) end;
				return(RealConsole:Error(`{Target.Name}:{Response}`, MonoFont))
			end;
			local Module	= FindModule(Target);
			if(Module) then return(RunModule(Module)) end;
			return(require(Target));
		elseif(type(Target) == 'string') then
			local Found	= Owner:FindFirstChild(Target);
			if(not Found and Owner.Parent) then Found = Owner.Parent:FindFirstChild(Target) end;
			if(Found and Found:IsA('ModuleScript')) then return RunModule(Found) end
			return(RealConsole:Error(`{Target} is missing from Model`, MonoFont))
		end
		return require(Target::ModuleScript)
	end;
end;

function RunModule(Module)
	if(RequireCache[Module] ~= nil) then return RequireCache[Module] end;
	local Source	= ScriptSources[Module];

	if(Source == nil) then
		local Loadable, Response = pcall(require, Module);
		if(Loadable) then return(Response) end;
		return(RealConsole:Error(`{Module:GetFullName()} has no Source`, MonoFont));
	end;

	RequireCache[Module]	= false;

	setthreadidentity(8)
	local Loader, Error = loadstring('return function(script, require, ...)\n' .. Source .. '\nend', '=' .. Module.Name);
	setthreadidentity(2)

	if(not Loader) then return(RealConsole:Error(`'{Module.Name}':{Error}`, MonoFont)) end;

	local Result			= Loader()(Module, BuildRequire(Module));
	RequireCache[Module]	= Result;

	return(Result);
end;

function Reify.Require(Inst)
	if(typeof(Inst) ~= 'Instance') then return(RealConsole:Error('Expected Reify Instance')) end;
	local Module	= FindModule(Inst);
	if(not Module) then return(RealConsole:Error('No ModuleScript found in ' .. Inst:GetFullName())) end;
	return(RunModule(Module));
end;

return(Reify)
