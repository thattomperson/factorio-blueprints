-- Minimal mock of the Factorio runtime, just enough to drive control.lua.
local handlers, log = {}, {}
serpent = { line = function(t) local function s(v) if type(v)=="table" then local k={} for a in pairs(v) do k[#k+1]=tostring(a) end table.sort(k) local o={} for _,a in ipairs(k) do o[#o+1]=a.."="..s(v[a] or v[tonumber(a)]) end return "{"..table.concat(o,",").."}" end return tostring(v) end return s(t) end }
table.deepcopy = nil -- not available in the real runtime stage
prototypes = { tile = { concrete={items_to_place_this={{name="concrete"}}}, ["refined-concrete"]={items_to_place_this={{name="refined-concrete"}}}, ["stone-path"]={items_to_place_this={{name="stone-brick"}}}, ["lab-dark-1"]={}, ["lab-dark-2"]={}, grass={} }, entity = setmetatable({}, {__index=function(_,n) return {tile_width=2,tile_height=2,fast_replaceable_group=(n:find('furnace') and 'furnace' or nil)} end}) }
local orders = {upgrade={}, decon={}, built={}, tile_decon={}}
defines = { events = setmetatable({}, {__index=function(_,k) return k end}), controllers = {character=1, remote=2, god=3}, build_mode={forced=1, superforced=2} }
script = { on_nth_tick=function(n,f) handlers.nth_tick=f end, register_on_object_destroyed=function() end, on_init=function(f) handlers.init=f end, on_configuration_changed=function() end,
  on_event=function(e,f) handlers[e]=f end }
storage = {}
local surfaces, entities = {}, {}
local function in_area(p, a) if not a then return true end
  local lt = a.left_top or a[1]; local rb = a.right_bottom or a[2]
  local x1, y1 = lt.x or lt[1], lt.y or lt[2]; local x2, y2 = rb.x or rb[1], rb.y or rb[2]
  return p.x>=x1 and p.x<=x2 and p.y>=y1 and p.y<=y2 end
local uid=0
local function new_entity(p) uid=uid+1 local e = { unit_number=uid, direction=p.direction or 0, valid=true, name=p.name, type=p.type or p.name, position=p.position, force=p.force, surface=p.surface, ghost_name=p.inner_name }
  e.destroy=function() e.valid=false end
  e.silent_revive=function() e.valid=false
    if e.type=="tile-ghost" then e.surface.set_tiles({{name=e.ghost_name, position={x=math.floor(e.position.x), y=math.floor(e.position.y)}}}) return {}, nil, nil end
    local r=new_entity{name=e.ghost_name, position=e.position, surface=e.surface, force={name="player"}} entities[#entities+1]=r return {}, r, nil end
  e.cancel_deconstruction=function() end
  setmetatable(e, {__newindex=function(t,k,v) if k=='minable' then error('LuaEntity::minable is read only.') end rawset(t,k,v) end})
  e.order_upgrade=function(p) orders.upgrade[#orders.upgrade+1]={e=e,target=p.target.name} end
  e.order_deconstruction=function() orders.decon[#orders.decon+1]=e end
  return e end
local function new_surface(name) local s = {name=name, valid=true}
  s.request_to_generate_chunks=function() end; s.force_generate_chunk_requests=function() end
  s.create_entity=function(p) p.surface=s local e=new_entity(p) entities[#entities+1]=e return e end
  s.find_entity=function(n,p) for _,e in ipairs(entities) do if e.valid and e.surface==s and e.name==n and e.position.x==p.x and e.position.y==p.y then return e end end end
  s.clone_area=function(p) local dx=p.destination_area.left_top.x-p.source_area.left_top.x local dy=p.destination_area.left_top.y-p.source_area.left_top.y
    for _,e in ipairs(entities) do if e.valid and e.surface==s and e.position.x>=p.destination_area.left_top.x and e.position.x<=p.destination_area.right_bottom.x and e.position.y>=p.destination_area.left_top.y and e.position.y<=p.destination_area.right_bottom.y then e.valid=false end end
    local snap={} for _,e in ipairs(entities) do snap[#snap+1]=e end
    for _,e in ipairs(snap) do if e.valid and e.surface==s and e.position.x>=p.source_area.left_top.x and e.position.x<=p.source_area.right_bottom.x and e.position.y>=p.source_area.left_top.y and e.position.y<=p.source_area.right_bottom.y then s.create_entity{name=e.name,type=e.type,position={x=e.position.x+dx,y=e.position.y+dy}} end end end
  s.tiles, s.hidden, s.decon = {}, {}, {}
  local function key(x,y) return math.floor(x)..","..math.floor(y) end
  local function base(x,y) return (name=="nauvis") and "grass" or (((math.floor(x)+math.floor(y))%2==0) and "lab-dark-1" or "lab-dark-2") end
  s.tile_name=function(x,y) return s.tiles[key(x,y)] or base(x,y) end
  s.set_tiles=function(t) s.tiles_set=(s.tiles_set or 0)+#t
    for _,v in ipairs(t) do local p=v.position local x,y=p.x or p[1], p.y or p[2] local k=key(x,y)
      local old=s.tile_name(x,y) local placeable=#(prototypes.tile[v.name].items_to_place_this or {})>0
      if placeable and #(prototypes.tile[old].items_to_place_this or {})==0 then s.hidden[k]=old end
      if not placeable then s.hidden[k]=nil end
      s.tiles[k]=v.name s.decon[k]=nil end end
  s.get_hidden_tile=function(p) return s.hidden[key(p.x or p[1], p.y or p[2])] end
  s.get_tile=function(x,y) local k=key(x,y) local t={valid=true, name=s.tile_name(x,y), position={x=math.floor(x),y=math.floor(y)}}
    t.to_be_deconstructed=function() return s.decon[k]==true end
    t.order_deconstruction=function() s.decon[k]=true orders.tile_decon[#orders.tile_decon+1]=k return {} end
    t.cancel_deconstruction=function() s.decon[k]=nil end
    return t end
  s.find_tiles_filtered=function(f) local r={} local lt, rb = f.area[1] or f.area.left_top, f.area[2] or f.area.right_bottom
    local names={} for _,n in ipairs(f.name or {}) do names[n]=true end
    for k,n in pairs(s.tiles) do local x,y=k:match("(-?%d+),(-?%d+)") x,y=tonumber(x),tonumber(y)
      if x+0.5>=lt.x and x+0.5<=rb.x and y+0.5>=lt.y and y+0.5<=rb.y and (not f.name or names[n]) then r[#r+1]=s.get_tile(x,y) end end return r end
  local function type_ok(f,e) if not f.type then return true end if type(f.type)=="string" then return e.type==f.type end for _,t in ipairs(f.type) do if e.type==t then return true end end return false end
  s.find_entities_filtered=function(f) local r={} for _,e in ipairs(entities) do if e.valid and e.surface==s and (not f.name or e.name==f.name) and type_ok(f,e) and in_area(e.position, f.area) then r[#r+1]=e end end return r end
  return s end
local nauvis = new_surface("nauvis"); nauvis.index=1; surfaces[1]=nauvis
local function blueprint_stack()
  local st = { valid_for_read=false, is_blueprint=false, label=nil }
  st.clear=function() st.valid_for_read=false st.ents=nil st.tiles=nil end
  st.set_stack=function(x) st.valid_for_read=true st.is_blueprint=true st.ents=nil st.tiles=nil end
  st.get_blueprint_tiles=function() return st.tiles end
  st.set_blueprint_tiles=function(t) st.tiles=t end
  st.is_blueprint_setup=function() return st.ents ~= nil end
  st.create_blueprint=function(p) local r={} local a=p.area for _,e in ipairs(entities) do if e.valid and e.surface.name==p.surface.name and e.name~="bpd-editor-radar" and e.position.x>=a.left_top.x and e.position.x<=a.right_bottom.x and e.position.y>=a.left_top.y and e.position.y<=a.right_bottom.y then r[#r+1]={entity_number=#r+1,name=e.name,position=e.position} end end local tl={} for k,n in pairs(p.surface.tiles) do local x,y=k:match("(-?%d+),(-?%d+)") x,y=tonumber(x),tonumber(y)
    if #(prototypes.tile[n].items_to_place_this or {})>0 and x>=a.left_top.x and x<a.right_bottom.x and y>=a.left_top.y and y<a.right_bottom.y then tl[#tl+1]={name=n, position={x=x,y=y}} end end
    if #tl>0 then st.tiles=tl end if #r>0 then st.ents=r end end
  st.get_blueprint_entities=function() return st.ents end
  st.set_blueprint_entities=function(t) st.ents=t end
  st.set_blueprint_entity_tags=function(i,t) st.ents[i].tags=t end
  st.export_stack=function() return "EXPORT:"..serpent.line(st.ents) end
  st.import_stack=function(s) st.valid_for_read=true st.is_blueprint=true st.imported=s return 0 end
  st.build_blueprint=function(p) if p.surface.name~='bpd-designer' then orders.built[#orders.built+1]={name=st.ents[1].name,pos=p.position,dir=st.ents[1].direction,mode=p.build_mode} return {} end for _,t in ipairs(st.tiles or {}) do p.surface.create_entity{name="tile-ghost", type="tile-ghost", inner_name=t.name, position={x=p.position.x+t.position.x+0.5,y=p.position.y+t.position.y+0.5}} end
    local g={} for _,e in ipairs(st.ents or {}) do g[#g+1]=p.surface.create_entity{name="entity-ghost", type="entity-ghost", inner_name=e.name, position={x=p.position.x+e.position.x,y=p.position.y+e.position.y}} end return g end
  return st end
game = { surfaces = surfaces, tick=0 }
game.create_surface=function(n) local s=new_surface(n) s.index=2 surfaces[n]=s surfaces[2]=s return s end
game.create_inventory=function() return { valid=true, [1]=blueprint_stack() } end
rendering = { draw_rectangle=function() return {valid=true, destroy=function() end} end, draw_text=function() return {valid=true, destroy=function() end} end }
local gui_root=function() local root={children={}} root.add=function(p) local el={name=p.name, tags=p.tags, style={}, children={}, valid=true} el.add=root.add el.add_tab=function() end el.destroy=function() el.valid=false if p.name then root[p.name]=nil end end if p.name then root[p.name]=el end return el end return root end
local player = { index=1, force={chart=function() end}, controller_type=1, surface=nauvis, cursor_stack=blueprint_stack(), printed={},
  gui={screen=gui_root(), top=gui_root()} }
player.print=function(m) player.printed[#player.printed+1]=m end
player.clear_cursor=function() player.cursor_stack.clear() return true end
player.set_controller=function(p) player.controller_type=p.type player.surface=p.surface end
player.exit_remote_view=function() player.controller_type=1 player.surface=nauvis handlers.on_player_controller_changed({player_index=1}) end
player.create_local_flying_text=function() end
game.get_player=function() return player end
package.path = arg[1].."/?.lua;"..package.path
require("control")
handlers.init()
local function check(c,m) if not c then error("FAIL: "..m) end print("ok  "..m) end
-- 1. hotkey with empty cursor opens window
handlers["bpd-toggle"]({player_index=1})
check(player.gui.screen.bpd_window ~= nil, "empty cursor opens designs window")
-- 2. hold a foreign blueprint -> import + enter
player.gui.screen.bpd_window.destroy()
local c=player.cursor_stack; c.set_stack("blueprint"); c.label="Smelter"; c.ents={{entity_number=1,name="stone-furnace",position={x=0,y=0}},{entity_number=2,name="inserter",position={x=1,y=0}}}
handlers["bpd-toggle"]({player_index=1})
check(storage.editing[1] and storage.editing[1].design_id==1, "held blueprint imported and editing design 1")
check(player.controller_type==2 and player.surface.name=="bpd-designer", "player is in remote view on designer")
check(storage.designs[1].name=="Smelter", "design named from blueprint label")
-- 3. place a ghost inside the cell -> revived
local g = surfaces["bpd-designer"].create_entity{name="entity-ghost", type="entity-ghost", inner_name="steel-furnace", position={x=5,y=5}}
handlers.on_built_entity({entity=g, player_index=1})
check(not g.valid and entities[#entities].name=="steel-furnace", "ghost on designer revived")
local far = surfaces["bpd-designer"].create_entity{name="entity-ghost", type="entity-ghost", inner_name="inserter", position={x=120,y=0}}
handlers.on_built_entity({entity=far, player_index=1})
check(not far.valid, "ghost outside cell rejected")
-- 4. save & return via the bar button
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
check(storage.editing[1]==nil and player.controller_type==1, "left designer")
check(storage.designs[1].tiers[1].version==1, "version 1 after first save")
check(player.cursor_stack.imported and player.cursor_stack.imported:find("bpd_design"), "blueprint with marker tags delivered to cursor")
-- 5. hold the delivered blueprint -> edits same design, not a new import
player.cursor_stack.ents = storage.scratch[1].ents
handlers["bpd-toggle"]({player_index=1})
check(storage.editing[1] and storage.editing[1].design_id==1 and storage.next_design_id==2, "re-editing own blueprint reuses design")
-- 6. escape out of remote view auto-saves (unchanged)
player.exit_remote_view()
check(storage.editing[1]==nil and storage.designs[1].tiers[1].version==1, "escape auto-saves, unchanged version stays 1")


-- ===== part 2/3 =====
local T = require("scripts.transform")
local t = T.from_placement(4,false,false)
local w = T.offset(t,{x=1,y=0}); check(w.x==0 and w.y==1, "rotate east: (1,0)->(0,1)")
check(T.direction(t,0)==4, "rotate east: north-facing becomes east")
local fx = T.compose(T.from_placement(0,true,false), T.from_placement(4,false,false))
local w2 = T.offset(fx,{x=1,y=0}); check(w2.x==0 and w2.y==1 and fx.f, "compose flip after rotate")
local D = require("scripts.diff")
local p = D.plan({{name="stone-furnace",position={x=1,y=1}},{name="inserter",position={x=3,y=1}},{name="pole",position={x=5,y=5}}},
                 {{name="steel-furnace",position={x=1,y=1}},{name="inserter",position={x=3,y=1},direction=8},{name="lamp",position={x=7,y=7}}})
check(#p.upgrade==1 and #p.remove==2 and #p.add==2, "plan: 1 upgrade, pole+old inserter removed, lamp+rotated inserter added")
-- give player the saved blueprint and place it in the world rotated east at (100,100)
local saved = storage.scratch[1]
local d1 = storage.designs[1]
local marker_tags
for _,e in ipairs(saved.ents) do if e.name=="bpd-marker" then marker_tags=e.tags end end
check(marker_tags and marker_tags.bpd_design==1, "saved blueprint carries marker tags")
game.tick = 5
handlers.on_pre_build({player_index=1, tick=5, direction=4, position={x=100,y=100}})
local mg = nauvis.create_entity{name="entity-ghost", type="entity-ghost", inner_name="bpd-marker", position={x=100.5,y=100.5}}
handlers.on_built_entity({entity=mg, player_index=1, tags=marker_tags})
local inst; for _,i in pairs(storage.instances) do inst=i end
check(inst and inst.t.k==1 and inst.design==1, "placed copy tracked with east rotation")
-- world furnace for that copy: snapshot offset of stone-furnace relative to marker
local snap = d1.tiers[1].snapshot
local sf; for _,e in ipairs(snap) do if e.name=="stone-furnace" then sf=e end end
local wp = T.world(inst.t, inst.marker.position, sf.position)
local wf = nauvis.create_entity{name="stone-furnace", position=wp}
-- edit design: replace stone furnace in cell with steel furnace, save -> v2
handlers.on_gui_click({player_index=1, element={tags={bpd="edit", design=1}}})
for _,e in ipairs(entities) do if e.valid and e.name=="stone-furnace" and e.surface.name=="bpd-designer" then e.valid=false surfaces["bpd-designer"].create_entity{name="steel-furnace", position=e.position} end end
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})

check(d1.tiers[1].version==2 and d1.tiers[1].snapshots[1] ~= nil, "design now v2, v1 snapshot kept")
local gui = require("scripts.gui")
handlers.on_gui_click({player_index=1, element={tags={bpd="update", inst=inst.id}}})

check(#orders.upgrade==1 and orders.upgrade[1].e==wf and orders.upgrade[1].target=="steel-furnace", "update orders stone->steel upgrade on the world furnace")
check(inst.version==2, "copy now at v2")
-- new tier
handlers.on_gui_click({player_index=1, element={tags={bpd="edit", design=1}}})
handlers.on_gui_click({player_index=1, element={tags={bpd="new_tier"}}})
check(storage.editing[1].tier==2 and d1.tiers[2], "new tier 2 created and being edited")
local n2=0 for _,e in ipairs(entities) do if e.valid and e.surface.name=="bpd-designer" and e.position.x>200 and e.name~="bpd-editor-radar" then n2=n2+1 end end
check(n2 >= 3, "tier 2 cell cloned from tier 1 ("..n2.." entities)")
surfaces["bpd-designer"].create_entity{name="lamp", position={x=256+10.5,y=0.5}}
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
handlers.on_gui_click({player_index=1, element={tags={bpd="upgrade", inst=inst.id}}})
local lampbuilt; for _,b in ipairs(orders.built) do if b.name=="lamp" then lampbuilt=b end end
check(inst.tier==2 and lampbuilt, "upgrade to T2 places the new lamp ghost")
check(math.abs(lampbuilt.pos.x - (inst.marker.position.x - 0)) < 1e9, "lamp placed at transformed position")
-- downgrade back to T1: the lamp that T2 added is marked for removal
local lampsnap; for _,e in ipairs(d1.tiers[2].snapshot) do if e.name=="lamp" then lampsnap=e end end
local wl = nauvis.create_entity{name="lamp", position=T.world(inst.t, inst.marker.position, lampsnap.position)}
local dbefore=#orders.decon
handlers.on_gui_click({player_index=1, element={tags={bpd="downgrade", inst=inst.id}}})
check(inst.tier==1 and inst.version==d1.tiers[1].version, "downgrade moves copy to T1 latest")
local lampgone=false for i=dbefore+1,#orders.decon do if orders.decon[i]==wl then lampgone=true end end
check(lampgone, "downgrade marks the T2-only lamp for removal")
handlers.on_gui_click({player_index=1, element={tags={bpd="downgrade", inst=inst.id}}})
check(inst.tier==1 and player.printed[#player.printed][1]=="bpd.err-lowest-tier", "cannot downgrade below T1")
handlers.on_gui_click({player_index=1, element={tags={bpd="upgrade", inst=inst.id}}})
check(inst.tier==2, "upgraded back to T2")
local before=#orders.decon
handlers.on_gui_click({player_index=1, element={tags={bpd="force", inst=inst.id}}})
print("force match decon ordered:", #orders.decon-before, "builds:", #orders.built)
-- ===== delete tier =====
local DS = require("scripts.designs")
-- create T3 from T2 with an extra pole, save it, and remember its saved blueprint tags
handlers.on_gui_click({player_index=1, element={tags={bpd="edit", design=1}}})
handlers.on_gui_click({player_index=1, element={tags={bpd="goto_tier", tier=2}}})
handlers.on_gui_click({player_index=1, element={tags={bpd="new_tier"}}})
check(storage.editing[1].tier==3, "T3 created")
surfaces["bpd-designer"].create_entity{name="small-electric-pole", position={x=512+20.5,y=0.5}}
handlers.on_gui_click({player_index=1, element={tags={bpd="save"}}})
local t3_tags; for _,e in ipairs(storage.scratch[1].ents) do if e.name=="bpd-marker" then t3_tags=e.tags end end
check(t3_tags.bpd_tier==3 and t3_tags.bpd_rev==0, "T3 blueprint tagged tier 3, rev 0")
local t3_version = d1.tiers[3].version
-- go to T2 (has the tracked copy) and ask to delete
handlers.on_gui_click({player_index=1, element={tags={bpd="goto_tier", tier=2}}})
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_tier"}}})
check(player.gui.screen.bpd_confirm_delete_tier ~= nil, "delete asks for confirmation")
check(DS.max_tier(d1)==3, "nothing deleted before confirming")
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_tier_confirm", design=1, tier=2}}})
check(DS.max_tier(d1)==2 and d1.tiers[3]==nil, "design now has 2 tiers")
check(d1.tiers[2].tier==2 and d1.tiers[2].version==t3_version, "old T3 moved down to T2 with its versions")
check(storage.instances[inst.id]==nil and not inst.marker.valid, "copy on deleted tier unlinked and its marker removed")
check(storage.editing[1].tier==1, "editor moved to T1")
local pole2=false for _,e in ipairs(entities) do if e.valid and e.name=="small-electric-pole" and e.surface.name=="bpd-designer" then
  if e.position.x>200 and e.position.x<400 then pole2=true end
  check(e.position.x<400, "no pole left in the old T3 column") end end
check(pole2, "old T3 contents now in the T2 column")
local m2=0 for _,e in ipairs(entities) do if e.valid and e.name=="bpd-marker" and e.surface.name=="bpd-designer" then m2=m2+1 end end
check(m2==2, "one marker per remaining cell ("..m2..")")
check(d1.tiers[2].marker.valid and d1.tiers[2].marker.position.x==256.5, "T2 marker re-found in its column")
check(DS.resolve_tier(d1,3,0)==2 and DS.resolve_tier(d1,2,0)==nil and DS.resolve_tier(d1,1,0)==1 and DS.resolve_tier(d1,2,1)==2, "old tier numbers resolve")
-- placing the old T3 blueprint registers a copy on (new) T2
game.tick = 9
local mg3 = nauvis.create_entity{name="entity-ghost", type="entity-ghost", inner_name="bpd-marker", position={x=300.5,y=300.5}}
handlers.on_built_entity({entity=mg3, player_index=1, tags=t3_tags})
local inst3; for _,i in pairs(storage.instances) do inst3=i end
check(inst3 and inst3.tier==2 and inst3.version==t3_version, "old T3 blueprint maps to T2")
-- a blueprint of the deleted tier is not tracked
local mgx = nauvis.create_entity{name="entity-ghost", type="entity-ghost", inner_name="bpd-marker", position={x=400.5,y=400.5}}
handlers.on_built_entity({entity=mgx, player_index=1, tags={bpd_design=1, bpd_tier=2, bpd_version=1}})
local n=0 for _ in pairs(storage.instances) do n=n+1 end
check(n==1 and not mgx.valid, "blueprint of the deleted tier is dropped")
-- delete down to one tier, then the last one is refused
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_tier_confirm", design=1, tier=1}}})
check(DS.max_tier(d1)==1 and inst3.tier==1, "deleting T1 moves T2 (and its copy) down")
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_tier"}}})
check(player.gui.screen.bpd_confirm_delete_tier == nil and DS.max_tier(d1)==1, "only tier cannot be deleted")
-- ===== new GUI: designs window, copies window, delete design =====
local U = function() return storage.ui[1] end
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
player.cursor_stack.clear()
handlers["bpd-toggle"]({player_index=1})
check(player.gui.screen.bpd_window ~= nil and U().selected==1 and #U().refs.list.items==1, "designs window lists design 1 and selects it")
handlers.on_gui_text_changed({player_index=1, element={tags={bpd="search"}, text="zzz"}})
check(#U().refs.list.items==0, "search filters the list")
handlers.on_gui_text_changed({player_index=1, element={tags={bpd="search"}, text=""}})
check(#U().refs.list.items==1, "clearing the search shows it again")
handlers.on_gui_click({player_index=1, element={tags={bpd="import"}}})
check(player.printed[#player.printed][1]=="bpd.import-hold", "import with an empty cursor asks for a blueprint")
handlers.on_gui_click({player_index=1, element={tags={bpd="new"}}})
check(storage.editing[1] and storage.editing[1].design_id==2, "new design opens the editor")
surfaces["bpd-designer"].create_entity{name="lamp", position={x=4.5,y=256+4.5}}
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
check(DS.get(2).tiers[1].version==1 and DS.get(2).tiers[1].saved_tick~=nil, "design 2 saved with a timestamp")
handlers["bpd-toggle"]({player_index=1})
handlers.on_gui_text_changed({player_index=1, element={tags={bpd="rename", design=2}, text="Lamp block"}})
check(DS.get(2).name=="Lamp block", "rename from the details pane")
handlers.on_gui_selection_state_changed({player_index=1, element={tags={bpd="design_list"}, selected_index=1}})
check(U().selected==1, "picking a list item selects that design")
handlers.on_gui_click({player_index=1, element={tags={bpd="copies", design=1}}})
check(player.gui.screen.bpd_copies ~= nil and #U().copies.visible==1, "copies window shows design 1's copy")
handlers.on_gui_selection_state_changed({player_index=1, element={tags={bpd="filter_status"}, selected_index=2}})
check(#U().copies.visible==0, "outdated-only filter hides the up-to-date copy")
handlers.on_gui_selection_state_changed({player_index=1, element={tags={bpd="filter_status"}, selected_index=1}})
handlers.on_gui_selected_tab_changed({player_index=1, element={tags={bpd="copies_tab"}, selected_tab_index=2}})
check(U().copies.tab==2 and #U().copies.visible==1, "T1 tab shows the T1 copy")
handlers.on_gui_checked_state_changed({player_index=1, element={tags={bpd="select_all"}, state=true}})
check(U().copies.selected[inst3.id]==true, "select all selects the visible copy")
handlers.on_gui_click({player_index=1, element={tags={bpd="bulk_downgrade"}}})
check(inst3.tier==1, "bulk downgrade on T1 does nothing")
handlers.on_gui_click({player_index=1, element={tags={bpd="back", design=1}}})
check(player.gui.screen.bpd_window ~= nil and player.gui.screen.bpd_copies == nil, "back returns to the designs window")
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_design", design=1}}})
check(player.gui.screen.bpd_confirm_delete_design ~= nil and DS.get(1) ~= nil, "delete design asks first")
handlers.on_gui_click({player_index=1, element={tags={bpd="delete_design_confirm", design=1}}})
check(DS.get(1)==nil and storage.instances[inst3.id]==nil, "design deleted and its copy unlinked")
check(U().selected==2 and player.gui.screen.bpd_window ~= nil, "designs window reopens on the remaining design")
local left=0 for _,e in ipairs(entities) do if e.valid and e.surface.name=="bpd-designer" and e.position.y<128 then left=left+1 end end
check(left==0, "design 1's cells are empty")

-- ===== tiles =====
local DSU = require("scripts.surface")
local designer = surfaces["bpd-designer"]
local function ghosts_left(area) local n=0 for _,e in ipairs(designer.find_entities_filtered{area=area, type={"tile-ghost","entity-ghost"}}) do n=n+1 end return n end
player.cursor_stack.clear()
local c2=player.cursor_stack; c2.set_stack("blueprint"); c2.label="Paved"
c2.ents={{entity_number=1,name="lamp",position={x=2.5,y=2.5}}}
c2.tiles={{name="concrete",position={x=0,y=0}},{name="concrete",position={x=1,y=0}},{name="concrete",position={x=2,y=0}}}
handlers["bpd-toggle"]({player_index=1})
local pd = DS.get(storage.editing[1].design_id)
local pc = DSU.center(pd.id, 1)
local parea = DSU.area(pd.id, 1)
check(designer.tile_name(pc.x, pc.y)=="concrete" and designer.tile_name(pc.x+2, pc.y)=="concrete", "imported blueprint tiles are built on the designer")
check(ghosts_left(parea)==0, "no tile ghosts left after import")
-- a tile ghost placed by the player is built at once
local tg = designer.create_entity{name="tile-ghost", type="tile-ghost", inner_name="stone-path", position={x=pc.x+5.5,y=pc.y+5.5}}
handlers.on_built_entity({entity=tg, player_index=1})
check(designer.tile_name(pc.x+5, pc.y+5)=="stone-path" and not tg.valid, "tile ghost on the designer is built")
-- one the game placed without telling us is picked up by the periodic sweep
designer.create_entity{name="tile-ghost", type="tile-ghost", inner_name="stone-path", position={x=pc.x+6.5,y=pc.y+5.5}}
handlers.nth_tick({tick=30})
check(designer.tile_name(pc.x+6, pc.y+5)=="stone-path", "periodic sweep builds missed tile ghosts")
-- deconstructing a tile puts the lab floor back
local proxy = designer.create_entity{name="deconstructible-tile-proxy", type="deconstructible-tile-proxy", position={x=pc.x+6.5,y=pc.y+5.5}}
handlers.on_marked_for_deconstruction({entity=proxy, player_index=1})
check(designer.tile_name(pc.x+6, pc.y+5):find("^lab") and not proxy.valid, "tile deconstruction restores the lab floor")
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
local pcell = pd.tiers[1]
check(pcell.version==1 and #pcell.tiles==4, "saved tiles: 3 concrete + 1 stone path ("..#pcell.tiles..")")
for _,t in ipairs(pcell.tiles) do check(not t.name:find("^lab"), "lab floor is not captured ("..t.name..")") end
check(storage.scratch[1].get_blueprint_tiles() and #storage.scratch[1].get_blueprint_tiles()==4, "saved blueprint carries the tiles")
check(pcell.tiles[1].position.x==0 and pcell.tiles[1].position.y==0, "tile offsets are tile centres relative to the marker")
local v1_tags; for _,e in ipairs(storage.scratch[1].ents) do if e.name=="bpd-marker" then v1_tags=e.tags end end
-- place v1 in the world rotated east, and let "robots" lay its tiles
game.tick = 20
handlers.on_pre_build({player_index=1, tick=20, direction=4, position={x=1000,y=1000}})
local pmg = nauvis.create_entity{name="entity-ghost", type="entity-ghost", inner_name="bpd-marker", position={x=1000.5,y=1000.5}}
handlers.on_built_entity({entity=pmg, player_index=1, tags=v1_tags})
local pinst
for _,i in pairs(storage.instances) do if i.design==pd.id then pinst=i end end
check(pinst and pinst.t.k==1, "paved copy tracked, rotated east")
local function wt(t) local c=T.world(pinst.t, pinst.marker.position, t.position) return math.floor(c.x), math.floor(c.y) end
for _,t in ipairs(pcell.tiles) do local x,y=wt(t) nauvis.set_tiles({{name=t.name, position={x=x,y=y}}}) end
local first = pcell.tiles[1]
local fx, fy = wt(first)
check(fx==1000 and fy==1000, "tile at the marker's tile maps onto the marker's tile ("..fx..","..fy..")")
-- tile-only edit: remove one concrete, change stone path to refined concrete
handlers.on_gui_click({player_index=1, element={tags={bpd="edit", design=pd.id}}})
local pr = designer.create_entity{name="deconstructible-tile-proxy", type="deconstructible-tile-proxy", position={x=pc.x+2.5,y=pc.y+0.5}}
handlers.on_marked_for_deconstruction({entity=pr, player_index=1})
local rg = designer.create_entity{name="tile-ghost", type="tile-ghost", inner_name="refined-concrete", position={x=pc.x+5.5,y=pc.y+5.5}}
handlers.on_built_entity({entity=rg, player_index=1})
handlers.on_gui_click({player_index=1, element={tags={bpd="save_return"}}})
check(pcell.version==2 and pcell.tile_snapshots[1] and #pcell.tiles==3, "tile-only edit makes a new version")
-- safe update: refined concrete ghosted over the stone path, removed concrete marked for deconstruction
local dec0 = #orders.tile_decon
handlers.on_gui_click({player_index=1, element={tags={bpd="update", inst=pinst.id}}})
local sp; for _,t in ipairs(pcell.tiles) do if t.name=="refined-concrete" then sp=t end end
local sx, sy = wt(sp)
local rghost = nauvis.find_entities_filtered{area={{sx+0.1,sy+0.1},{sx+0.9,sy+0.9}}, type="tile-ghost"}
check(#rghost==1 and rghost[1].ghost_name=="refined-concrete", "update ghosts the changed tile at the rotated position")
local removed; for _,t in ipairs(pcell.tile_snapshots[1]) do if t.name=="concrete" and t.position.x==2 then removed=t end end
local ex, ey = wt(removed)
check(#orders.tile_decon==dec0+1 and orders.tile_decon[#orders.tile_decon]==ex..","..ey, "update marks the removed concrete for deconstruction")
check(pinst.version==2, "paved copy at v2")
-- unchanged concrete is not re-ghosted
local cx, cy = wt(pcell.tiles[1])
check(#nauvis.find_entities_filtered{area={{cx+0.1,cy+0.1},{cx+0.9,cy+0.9}}, type="tile-ghost"}==0, "matching tiles are left alone")
-- force match: a stray hand-laid concrete inside the footprint is removed, grass outside is untouched
nauvis.set_tiles({{name="concrete", position={x=997, y=1002}}})
local dec1 = #orders.tile_decon
handlers.on_gui_click({player_index=1, element={tags={bpd="force", inst=pinst.id}}})
local stray=false for i=dec1+1,#orders.tile_decon do if orders.tile_decon[i]=="997,1002" then stray=true end end
check(stray, "force match removes a stray tile inside the footprint")
local wrong=false for i=dec1+1,#orders.tile_decon do if orders.tile_decon[i]==cx..","..cy then wrong=true end end
check(not wrong, "force match keeps master tiles")
print("all passed")
