-- BITWISE
--
-- A bit-logic based sequencer intedned for live play.
--
-- ALL PAGES
-- > k1: exit
-- > e1: select page
-- > e2: select control
-- > + k1: adjust control probability
--
-- GATES PAGE controls
-- > OPERATOR:
-- >> k2 [+ k1]: and [nand]
-- >> k3 [+ k1]: or [xor]
-- >> e3: l/r rotate both
-- >> [+ k1]:[oposite directions]
-- > GATE BYTE:
-- >> k3 [+ k1]: not [reflect TODO] 
-- >> e3: l/r rotate
-- >> [+ k1]: l/r shift
-- >> [+ k2]: +/- value
-- >> [+ k1 k2]: +/- upper nibble
--
-- NOTES PAGE controls
-- > Each BIT SEQUENCE BYTE
-- >> k2 [+ k1]: not [momentary] 
-- >> k3 [ + k1]: reflect [momentary]
-- >> e3: l/r rotate
-- >> [+ k1]: l/r shift
-- >> [+ k2]: +/- value
-- >> [+ k1 k2]: +/- upper nibble
--
-- TODO
-- * implement probability (fix notes display)
-- * replace most state vars with params
-- * tick highlight arg and gates
-- * title all pages
-- * Check all funcs against docs
-- * rename arg to gates_2 or such
-- * POST
-- * EC: implement grid
-- * Clean up single-bit gate calc

engine.name = "PolyPerc"
-- Leftover from byte sequencer
-- s = require("sequins")
MusicUtil = require("musicutil")

local function bit8_rrot(n,d)
  -- if d==1, compliment is -7, if -2 then 6
  local d_8_compliment = -1 * math.floor(d/math.abs(d)) * (8 - math.abs(d))
  return bit32.band(0xFF,bit32.rshift(n,d) + bit32.rshift(n,d_8_compliment))
end

local function bit8_rshift(n,d)
  return bit32.band(0xFF,bit32.rshift(n,d))
end

local function bit8_bnot(n)
  return bit32.band(0xFF,bit32.bnot(n))
end

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
focus_control = 1

local function bit_value(n,b)
  return bit32.band(1,bit32.rshift(n,b-1))  
end


local function is_bit_set(n,b)
  return (bit_value(n,b) ~= 0)  
end

local function get_note_bit_bytes_step(step)
  local note = 0
  for i=1,#note_bit_bytes do
    local prob = note_bit_ps[i]
    note = note + (math.random() < prob and bit_value(note_bit_bytes[i],step)*math.floor(2^(i-1)) or 0)
  end
  return note
end

-- TODO separate root_note from base_note so you can have root_note for a scale with a different base note
function build_scale() 
  scale = MusicUtil.generate_scale(params:get("base_note"), params:get("scale_mode"),8)
end

function init()
  message = "BITWISE"
  screen_dirty = true
  redraw_clock_id = clock.run(redraw_clock)

  local base_note_spec = controlspec.MIDINOTE
  base_note_spec.default = 24
  params:add_control("base_note","base note",base_note_spec)
  -- TODO debug why this is getting set to fractional in the params screen
  params:set_action("base_note", function(n) base_note = math.floor(n) end)
  base_note = params:get("base_note")

  local scale_names = {}
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  params:add({
    type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end
  })

  build_scale()

  notes = {}
  note_bit_bytes = {
    0x55,
    0x33,
    0xe5,
    0xf0,
  }
  gates = 0x55
  arg = 0x33
  op = "or"
  note_bit_ps = {1,1,1,1}
  arg_p = 1
  gates_p = 1
  op_p = 0
  
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
        local bit_num = ((tick - 1) % op_period) + 1
        -- local seq_op
        -- if seq_op == nil or arg == nil or (tick % op_period) == 1 then
          -- arg = args_seq()  
          -- seq_op = ops_seq()
        -- end
        op = gate_op -- or seq_op
        -- TODO optimize this so we're not recalculating full byte each time
        local new_opd_gates = op_fns[op](math.random() < gates_p and gates or 0,math.random() < arg_p and arg or 0)
        new_opd_gates = math.random() < op_p and bit8_bnot(new_opd_gates) or new_opd_gates
        -- only update current bit
        -- (overwrite that bit in opd_gates by setting to try then anding with new product)
        opd_gates = bit32.bor(bit32.band(opd_gates,0xFF-2^(bit_num-1)),bit32.band(new_opd_gates,2^(bit_num-1)))
        local note = base_note + get_note_bit_bytes_step(bit_num)
        notes[bit_num] = note
        -- TODO add MIDI out option
        if is_bit_set(opd_gates,bit_num) then
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

keys = {} -- track keys depressed at any point

function enc(e, d)
  turn(e, d)
  screen_dirty = true
end

function turn(e, d) ----------------------------- an encoder has turned
  screen_dirty = true
  if e == 1 then
    active_mode = util.clamp(active_mode + d,1,2)
    focus_control = 1
    redraw()
    return
  end
  if active_mode == 1 then
    if e == 2 then
      if keys[1] == 1 then
        if focus_control == 1 then
          op_p = util.clamp(op_p+d/10,0,1)
        elseif focus_control == 2 then
          gates_p = util.clamp(gates_p+d/10,0,1)
        elseif focus_control == 3 then
          arg_p = util.clamp(arg_p+d/10,0,1)
        end
      else
        focus_control= util.clamp(focus_control + d,1,3)
      end
    elseif e == 3 then
      if focus_control == 1 then
        -- if k[1] is down, move arg and gates in op directions
        local inverse = (keys[1] == 1) and -1 or 1 
        gates = bit8_rrot(gates,d)
        arg = bit8_rrot(arg,inverse*d)
      else
        if keys[2] == 1 then
          -- inc byte / most significant nibble
          local amt = d * ((keys[1] == 1) and 0x10 or 1)
          if focus_control == 2 then
            gates = util.wrap(gates+amt,0,256)
          else
            arg = util.wrap(arg+amt,0,256)
          end
        else
          -- rot / shift
          local enc_op = (keys[1] ~= 1) and bit8_rrot or bit8_rshift
          if focus_control == 2 then
            gates = enc_op(gates,d)
          else
            arg = enc_op(arg,d)
          end
        end
      end
    end
  elseif active_mode == 2 then
    if (e==2) then
      if keys[1] == 1 then
        note_bit_ps[focus_control] = util.clamp(note_bit_ps[focus_control] + d/10,0,1)
      else
        focus_control= util.clamp(focus_control + d,1,4)
      end
    elseif (e==3) then
      -- TODO confirm this is a reference
      local subject = note_bit_bytes[focus_control]
      if keys[2] == 1 then
        -- inc byte / most significant nibble depending on k[1]
        local amt = d * ((keys[1] == 1) and 0x10 or 1)
        note_bit_bytes[focus_control]= util.wrap(subject+amt,0,256)
      else
        -- rot / shift depends on k[1]
        local enc_op = (keys[1] ~= 1) and bit8_rrot or bit8_rshift
        note_bit_bytes[focus_control]= enc_op(subject,d)
      end
    end
  end
end

function key(k, z)
  keys[k] = z == 1 and 1 or nil
  -- lazy: always redraw on key action
  screen_dirty = true
  if active_mode == 1 then
    if focus_control == 1 then
      -- complex op assignment logic here
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
    else
      if k == 3 then
        -- momentary if k[1], toggle otherwise
        if keys[1] == 1 or z == 1 then
          -- TODO simplify this logic by storing all state in a table and using reference to assign
          if focus_control == 2 then
            gates = bit8_bnot(gates)
          else
            arg = bit8_bnot(arg)
          end
        else
          -- TODO implement reflection
        end
      end
    end
  elseif active_mode == 2 then
    if z == 1 then
      if k == 3 then
        note_bit_bytes[focus_control] = bit32.band(0xFF,bit32.bnot(note_bit_bytes[focus_control]))
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

function draw_bin(num,bits,x,y,w,h,level,on_h_ratio)
  level = level ~= nil and level or 6
  on_h_ratio = on_h_ratio ~= nil and on_h_ratio or 1
  local xd = w/bits
  -- screen.level(level)
  -- screen.rect(x,y,w,h)
  -- screen.stroke()
  for i=1,bits do
    local do_highlight = (8 - (tick - 1) % 8) == i
    -- draw background
    screen.level(do_highlight and 1 or 0)
    screen.rect(x+(i-1)*xd,y,xd,h)
    screen.fill()
    -- if on, draw overlay
    if bit32.band(num,2^(bits-i)) ~= 0 then
      screen.level(do_highlight and 15 or level)
      screen.rect(x+(i-1)*xd,y + h * (1 - on_h_ratio),xd,h * on_h_ratio)
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
    -- screen.move(4,24)
    -- screen.text(hexfmt(gates))
    screen.move(64,24)
    local op_level = focus_control == 1 and 10 or 2 
    screen.level(op_level)
    screen.text_center(op or "--")
    local op_text_width = screen.text_extents(op or "--")
    screen.move(64-math.floor(op_text_width/2)-6,24)
    screen.level(math.ceil(op_level * op_p))
    screen.text("!")
    -- screen.move(128,24)
    -- screen.text_right(hexfmt(arg))
    screen.font_size(8) ---------- set the size to 8
    -- screen.move(4,64)
    -- screen.text(tick or "--")
    -- screen.move(4, 7) ---------- move the pointer to x = 64, y = 32
    -- screen.text(message) 
    -- screen.fill() ---------------- fill the termini and message at once
    draw_bin(gates,8,10,28,106,8,focus_control == 2 and 8 or 2,gates_p)
    draw_bin(arg,8,10,36,106,8,focus_control == 3 and 8 or 2,arg_p)
    screen.level(15)
  elseif (active_mode == 2) then
    -- TODO add hex totals for each step
    screen.font_face(1) ---------- set the font face to "04B_03"
    screen.font_size(8) ---------- set the size to 8
    for i=1,4 do
      screen.level((focus_control == i) and 15 or 4)
      screen.move(1,i*10)
      screen.text(math.floor(2^(i-1)))
      draw_bin(note_bit_bytes[i],8,10,i*10-5,106,8,focus_control == i and 8 or 2,note_bit_ps[i])
    end
  end
  for i=1,8 do
    screen.move(16+((i-1)*106/8),52)
    screen.level(8 - ((tick - 1) % 8) == i and 15 or 2)
    screen.text_center(notes[9-i] and MusicUtil.note_num_to_name(scale[notes[9-i]]) or "")
    screen.fill()
  end
  draw_bin(opd_gates,8,10,54,106,8,6,1)
  screen.update() -------------- update space
end


function r() ----------------------------- execute r() in the repl to quickly rerun this script
  norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end