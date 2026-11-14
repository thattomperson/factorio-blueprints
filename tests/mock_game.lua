-- Minimal mock of the Factorio runtime, just enough to drive control.lua.
local handlers, log = {}, {}
serpent = { line = function(t) local function s(v) if type(v)=="table" then local k={} for a in pairs(v) do k[#k+1]=tostring(a) end table.sort(k) local o={} for _,a in ipairs(k) do o[#o+1]=a.."="..s(v[a] or v[tonumber(a)]) end return "{"..table.concat(o,",").."}" end return tostring(v) end return s(t) end }
table.deepcopy = nil -- not available in the real runtime stage
prototypes = { entity = setmetatable({}, {__index=function(_,n) return {tile_width=2,tile_height=2,fast_replaceable_group=(n:find('furnace') and 'furnace' or nil)} end}) }
local orders = {upgrade={}, decon={}, built={}}
defines = { events = setmetatable({}, {__index=function(_,k) return k end}), controllers = {character=1, remote=2, god=3}, build_mode={forced=1, superforced=2} }
script = { register_on_object_destroyed=function() end, on_init=function(f) handlers.init=f end, on_configuration_changed=function() end,
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
  e.silent_revive=function() e.valid=false local r=new_entity{name=e.ghost_name, position=e.position, surface=e.surface, force={name="player"}} entities[#entities+1]=r return {}, r, nil end
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
  s.set_tiles=function(t) s.tiles_set=(s.tiles_set or 0)+#t end
  s.find_entities_filtered=function(f) local r={} for _,e in ipairs(entities) do if e.valid and e.surface==s and (not f.name or e.name==f.name) and in_area(e.position, f.area) then r[#r+1]=e end end return r end
  return s end
local nauvis = new_surface("nauvis"); nauvis.index=1; surfaces[1]=nauvis
local function blueprint_stack()
  local st = { valid_for_read=false, is_blueprint=false, label=nil }
  st.clear=function() st.valid_for_read=false st.ents=nil end
  st.set_stack=function(x) st.valid_for_read=true st.is_blueprint=true st.ents=nil end
  st.is_blueprint_setup=function() return st.ents ~= nil end
  st.create_blueprint=function(p) local r={} local a=p.area for _,e in ipairs(entities) do if e.valid and e.surface.name==p.surface.name and e.name~="bpd-editor-radar" and e.position.x>=a.left_top.x and e.position.x<=a.right_bottom.x and e.position.y>=a.left_top.y and e.position.y<=a.right_bottom.y then r[#r+1]={entity_number=#r+1,name=e.name,position=e.position} end end if #r>0 then st.ents=r end end
  st.get_blueprint_entities=function() return st.ents end
  st.set_blueprint_entities=function(t) st.ents=t end
  st.set_blueprint_entity_tags=function(i,t) st.ents[i].tags=t end
  st.export_stack=function() return "EXPORT:"..serpent.line(st.ents) end
  st.import_stack=function(s) st.valid_for_read=true st.is_blueprint=true st.imported=s return 0 end
  st.build_blueprint=function(p) if p.surface.name~='bpd-designer' then orders.built[#orders.built+1]={name=st.ents[1].name,pos=p.position,dir=st.ents[1].direction,mode=p.build_mode} return {} end local g={} for _,e in ipairs(st.ents) do g[#g+1]=p.surface.create_entity{name="entity-ghost", type="entity-ghost", inner_name=e.name, position={x=p.position.x+e.position.x,y=p.position.y+e.position.y}} end return g end
  return st end
game = { surfaces = surfaces, tick=0 }
game.create_surface=function(n) local s=new_surface(n) s.index=2 surfaces[n]=s surfaces[2]=s return s end
game.create_inventory=function() return { valid=true, [1]=blueprint_stack() } end
rendering = { draw_rectangle=function() return {valid=true, destroy=function() end} end, draw_text=function() return {valid=true, destroy=function() end} end }
local gui_root=function() local root={children={}} root.add=function(p) local el={name=p.name, tags=p.tags, style={}, children={}, valid=true} el.add=root.add el.destroy=function() el.valid=false if p.name then root[p.name]=nil end end if p.name then root[p.name]=el end return el end return root end
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
print("all passed")
