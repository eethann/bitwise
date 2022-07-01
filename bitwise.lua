-- BITWISE
-- A bit-logic based sequencer intedned for live play.
--
-- ALL PAGES
-- > k1: exit
-- > e1: select page
-- > e2: select control
--
-- GATES PAGE controls
-- > OPERATOR:
-- >> k2 [+ k1]: and [nand]
-- >> k3 [+ k1]: or [xor]
-- >> e3: l/r rotate both
-- >> [+ k1]:[oposite directions]
-- > GATE BYTE:
-- >> k2 [+ k1]: not [momentary] 
-- >> k3 [ + k1]: reflect [momentary]
-- >> e3: +/- value
-- >> [+ k1]: +/- upper nibble
-- >> [+ k1 k2]: l/r rotate
-- >> [+ k1 k3]: l/r shift
--
-- NOTES PAGE controls
-- > Each BIT SEQUENCE BYTE
-- >> k2 [+ k1]: not [momentary] 
-- >> k3 [ + k1]: reflect [momentary]
-- >> e3: +/- value
-- >> [+ k1]: +/- upper nibble
-- >> [+ k1 k2]: l/r rotate
-- >> [+ k1 k3]: l/r shift

engine.name = "Thebangs"
-- Leftover from byte sequencer
-- s = require("sequins")
MusicUtil = require("musicutil")

op_fns = {
  xor = bit32.bxor,
  ["and"] = bit32.band,
  lrot = bit32.lrot,
  ["or"] = bit32.bor,
  nand = function(n,m) 
    return bit32.band(0xFF,bit32.bnot(bit32.band(n,m)))
  end
}

op = "or"
gates = 0x66
arg = 0x33

tick = 0
opd_gates = 0
active_mode = 1
modes = {"gates","notes"}
focust_control = 1

local function bit_value(n,b)
  return bit32.band(1,bit32.rshift(n,b-1))  
end


local function is_bit_set(n,b)
  return (bit_value(n,b) ~= 0)  
end

local function get_note_bit_bytes_step(step)
  local note = 0
  for i=1,#note_bit_bytes do
    note = note + bit_value(note_bit_bytes[i],step)*math.floor(2^(i-1))
  end
  return note
end

-- TODO separate root_note from base_note so you can have root_note for a scale with a different base note
function build_scale() 
  scale = MusicUtil.generate_scale(params:get("root_note"), params:get("scale_mode"),8)
end

function init()
  message = "BITWISE"
  screen_dirty = true
  redraw_clock_id = clock.run(redraw_clock)

  local base_note_spec = controlspec.MIDINOTE
  base_note_spec.default = 24
  params:add_control("base_note","base note",base_note_spec)
  params:set_action("base_note", function(n) base_note = n end)
  base_note = 24

  local scale_names
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  params:add({
    type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end
  })

  build_scale()

  note_bit_bytes = {
    0x55,
    0x33,
    0xe5,
    0xf0,
  }
  gates = 0x55
  arg = 0x33
  op = "or"
  
  tick = 0
  opd_gates = 0

  -- Left-overs from sequencer
  -- ops = {"xor","and","or","xor"}
  -- ops_seq = s(ops)
  
  -- args = {0x77,0xfc,0x81}
  -- args_seq = s(args)
  
  local op_period = 8
  div = 4
  
  gate_op = "or"
  
  sequence = clock.run(
    function()
      while true do
        clock.sync(1/div)
        tick = math.floor(clock.get_beats()*div)
        local seq_op
        -- if seq_op == nil or arg == nil or (tick % op_period) == 1 then
          -- arg = args_seq()  
          -- seq_op = ops_seq()
        -- end
        op = gate_op or seq_op
        opd_gates = op_fns[op](gates,arg)
        local note = base_note + get_note_bit_bytes_step(((tick - 1) % 8) + 1)
        -- TODO add MIDI out option
        if is_bit_set(opd_gates,((tick-1)%8)+1) then
          engine.hz(MusicUtil.note_num_to_freq(scale[note]))
        else
          -- engine.noteOff(0)    
        end
        -- message = " G:" .. string.format("%02x",gate) .. "/" .. string.format("%02x",opd_gates) .. " O:" .. (op or "--") .. " A:" .. (arg and string.format("%02x",arg) or "--") 
        -- print(message)
        screen.dirty = true
        redraw()
      end
    end
  )
end

local function hexfmt(n)
  if type(n) ~= "number" then return "" end
  return string.upper(string.format("%02x",n))
end

function enc(e, d) --------------- enc() is automatically called by norns
  if e == 1 then turn(e, d) end -- turn encoder 1
  if e == 2 then turn(e, d) end -- turn encoder 2
  if e == 3 then turn(e, d) end -- turn encoder 3
  screen_dirty = true ------------ something changed
end

keys = {}

function turn(e, d) ----------------------------- an encoder has turned
  if e == 1 then
    active_mode = util.clamp(active_mode + d,1,2)
    return
  end
  if active_mode == 1 then
    if (keys[1] == 1) then
      if (e == 2) then
        if (d > 0) then
          gates = bit32.band(0xFF,bit32.rshift(gates,1) + bit32.rshift(gates,-7))
        elseif (d < 0) then
          gates = bit32.band(0xFF,bit32.rshift(gates,-1) + bit32.rshift(gates,7))
        end
      elseif (e == 3) then
        if (d > 0) then
          arg = bit32.band(0xFF,bit32.rshift(arg,1) + bit32.rshift(arg,-7))
        elseif (d < 0) then
          arg = bit32.band(0xFF,bit32.rshift(arg,-1) + bit32.rshift(arg,7))
        end
      end
    else
      if (e == 2) then
        gates = util.wrap(gates+d,0,256)
      elseif (e == 3) then
        arg = util.wrap(arg+d,0,256)
      end
    end
  elseif active_mode == 2 then
    if (e==2) then
      if (keys[1] == 1) then
        note_bit_bytes[focust_control] = bit32.band(0xFF,bit32.rshift(note_bit_bytes[focust_control],d))
      else
        focust_control = util.clamp(focust_control + d,1,5)
      end
    elseif (e==3) then
      if (keys[1] == 1) then
        if (d > 0) then
          note_bit_bytes[focust_control] = bit32.band(0xFF,bit32.rshift(note_bit_bytes[focust_control],1) + bit32.rshift(note_bit_bytes[focust_control],-7))
        elseif (d < 0) then
          note_bit_bytes[focust_control] = bit32.band(0xFF,bit32.rshift(note_bit_bytes[focust_control],-1) + bit32.rshift(note_bit_bytes[focust_control],7))
        end
      else
        note_bit_bytes[focust_control] = util.clamp(note_bit_bytes[focust_control]+d,0,256)
      end
    end
  end
end

function key(k, z)
  keys[k] = z == 1 and 1 or nil
  if active_mode == 1 then
    if #keys == 0 then
      -- gate_op = nil
      -- return
    end
    if z == 1 then
      if (keys[1] ~= nil) then
        if (keys[2] ~= nil) then
          gate_op = "nand"
        elseif (keys[3] ~= nil) then
          gate_op = "xor"
        end
      else
        if (keys[2] ~= nil) then
          gate_op = "and"
        elseif (keys[3] ~= nil) then
          gate_op = "or"
        end
      end
      screen_dirty = true
    end
  elseif active_mode == 2 then
    if z == 1 then
      if k == 2 then
        note_bit_bytes[focust_control] = bit32.band(0xFF,bit32.bnot(note_bit_bytes[focust_control]))
        screen_dirty = true
      end
    end
  end
end

function press_down(i) ---------- a key has been pressed
  message = "press down " .. i -- build a message
end

-- TODO revisit clock draw code (currently not working)
function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if screen_dirty then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
  end
end

function draw_bin(num,bits,x,y,w,h,hilite_tick)
  local xd = w/bits
  screen.rect(x,y,w,h)
  screen.stroke()
  for i=1,bits do
    if bit32.band(num,2^(bits-i)) ~= 0 then
      screen.level((hilite_tick == nil or (8 - (tick - 1) % 8) == i) and 15 or 6)
      screen.rect(x+(i-1)*xd,y,xd,h)
      screen.fill()
    end
  end
end


function redraw() 
  screen.clear() --------------- clear space
  screen.aa(0) ----------------- enable anti-aliasing

  if (active_mode == 1) then
    screen.level(15) ------------- max
    screen.font_face(1) ---------- set the font face to "04B_03"
    screen.font_size(24) ---------- set the size to 8
    screen.move(4,24)
    screen.text(hexfmt(gates))
    screen.move(64,24)
    screen.text_center(op or "--")
    screen.move(128,24)
    screen.text_right(hexfmt(arg))
    screen.font_size(8) ---------- set the size to 8
    -- screen.move(4,64)
    -- screen.text(tick or "--")
    screen.move(4, 7) ---------- move the pointer to x = 64, y = 32
    screen.text(message) 
    screen.fill() ---------------- fill the termini and message at once
    draw_bin(gates,8,10,28,106,8)
    draw_bin(arg,8,10,36,106,8)
    draw_bin(opd_gates,8,10,54,106,8,true)
  elseif (active_mode == 2) then
    -- TODO add hex totals for each step
    screen.font_face(1) ---------- set the font face to "04B_03"
    screen.font_size(8) ---------- set the size to 8
    for i=1,4 do
      screen.level((focust_control == i) and 15 or 4)
      screen.move(1,i*10)
      screen.text(math.floor(2^(i-1)))
      draw_bin(note_bit_bytes[i],8,10,i*10-5,106,8,true)
    end
    for i=1,8 do
      local note = base_note + get_note_bit_bytes_step(9-i)
      screen.move(16+((i-1)*106/8),52)
      screen.level(8 - ((tick - 1) % 8) == i and 15 or 6)
      screen.text_center(MusicUtil.note_num_to_name(scale[note]))
    end
    draw_bin(opd_gates,8,10,54,106,8,true)
  end
  screen.update() -------------- update space
end


function r() ----------------------------- execute r() in the repl to quickly rerun this script
  norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end