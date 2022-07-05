-- BITWISE
-- v1.3.0 @spectralclockworks
-- https://llllllll.co/t/bitwise/56659
--
-- A probablistic bitwise sequencer
-- intended for live play.
--
-- UI is split into two pages: 
-- GATES and NOTES
--
-- ALL PAGES
-- > k1: exit
-- > e1: select page
-- > [+ k1]: Lock random
-- > e2: select control
-- > [+ k1]: Set randomness
-- > [+ k1 k2]: TBD
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
-- MORE INFO:
--
-- GATES for each step are 
-- generated by combining two 
-- bytes with the chosen 
-- bitwise operator.
-- 
-- NOTES for each step are 
-- calculated by construcing 
-- a 4 bit value out of the 
-- current bit for each of 4 
-- bytes (one for each power 
-- of 2).
--
-- All controls can have a 
-- randomness amount. The
-- higher the randomness
-- the more likely that 
-- control will be unstable.
--  Probability has two possible 
-- modes (set in a parameter).
--
-- "Stability" mode:
-- Acts like an ASR, prob
-- is the likelihood any bit
-- changes when it comes up.
-- Off means bits are totally
-- stable, middle means they 
-- have a 50% chance of
-- flipping, and 100% means
-- they will always flip.
--
-- "Trigger mode"
-- For any byte, the 
-- probability is the 
-- likelihood that a 1 bit is 
-- actually on when it
-- comes up..
--  
-- For the operator the 
-- probability chooses between 
-- the op and its logical 
-- inverse, in both modes.
--
-- Holding K1 and turning
-- E1 clockwise will "lock"
-- all randomness, looping
-- without changes. Turning
-- counter-clockwise will 
-- "unlock" and re-enable
-- the randomness levels
-- of each control.
-- 
-- TODO
-- * Add MIDI
-- * EC: implement grid
-- * Clean up single-bit gate calc
-- * replace most state vars with params
-- * title all pages ?
-- * add "mod" pages with flexible subjects (div, synth params, additional voices, etc)
-- * add a drum kit / sampler?
-- * add swing
-- * Refactor prob code so we don't need to invert the UI
-- * Add k1+e1 "lock all" option to manage randomness globally
-- * Add "focus all" for notes that edits all bytes together
-- * Add "reset" option to start ticks from 1 (clock start?)
-- * Add params for each interval of note bytes bits
-- * Reworkd UI for trigger prob to be clearer

engine.name = "PolyPerc"
-- Leftover from byte sequencer
-- s = require("sequins")
MusicUtil = require("musicutil")

-- 8 bit logic functions
local function bit8(n)
  return bit32.band(0xFF,n)
end

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

local function bit8_get_bit(n,b)
  return bit32.band(bit32.rshift(n,b-1),1)
end

local function bit8_set_bit(n,b,v)
  v = v == 0 and 0 or 1
  return bit32.bor(bit32.band(n,bit8_bnot(bit32.lshift(1,b-1))),bit8(bit32.lshift(v,b-1)))
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

gate_op = "or"
gates = 0x66
gates_2 = 0x33

tick = 0
calcd_gates = 0
active_mode = 1
modes = {"gates","notes"}
focus_control = 1

local function bit_value(n,b)
  return bit32.band(1,bit32.rshift(n,b-1))  
end

local function is_bit_set(n,b)
  return (bit_value(n,b) ~= 0)  
end

local function coin_flip(p)
  return lock_probs 
    or (p == 1 and true)
    or (p == 0 and false)
    or (math.random() < p)
end

local function get_note_bit_bytes_step(step)
  local note = 0
  for i=1,#note_bit_bytes do
    local flip = prob_mode == 2 and coin_flip(note_bit_ps[i]) or true
    note = note + (flip and bit_value(note_bit_bytes[i],step)*params:get("interval_"..i) or 0)
  end
  return note
end

local function prob_flip_bit(num,bit,prob)
  local mask = bit32.lshift(1,bit-1)
  return coin_flip(prob) and num or bit8(bit32.bxor(num,mask))
  -- return coin_flip(prob) and num or bit8_set_bit(num, bit, bit8_get_bit(num, bit) == 1 and 0 or 1)
end

-- TODO separate root_note from base_note so you can have root_note for a scale with a different base note
function build_scale() 
  scale = MusicUtil.generate_scale(params:get("base_note"), params:get("scale_mode"),8)
end

function set_base_note(n)
  base_note = n
  build_scale()
end

function init()
  message = "BITWISE"
  screen_dirty = true
  redraw_clock_id = clock.run(redraw_clock)

  params:add_separator("Bitwise")
  params:add_group("Notes",6)
  local base_note_spec = controlspec.MIDINOTE:copy()
  base_note_spec.default = 24
  base_note_spec.step = 1
  params:add_control("base_note","base note",base_note_spec,function(param) return MusicUtil.note_num_to_name(param:get(),true) end)
  -- TODO debug why this is getting set to fractional in the params screen
  params:set_action("base_note", set_base_note)
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

  params:add_number("interval_1","interval 1", -24, 24, 1)
  params:add_number("interval_2","interval 2", -24, 24, 2)
  params:add_number("interval_3","interval 3", -24, 24, 4)
  params:add_number("interval_4","interval 4", -24, 24, 8)

  params:add_group("Probability",2)
  params:add_binary("lock_probs", "Lock Current State (on/off)", "toggle")
  -- TODO Change to setter func
  params:set_action("lock_probs", function(v) lock_probs = v end)

  params:add_option("prob_mode","Probability Mode",{"stability","trigger"},1)
  params:set_action("prob_mode", function(n) prob_mode = n end)
  prob_mode = params:get("prob_mode")

  -- TODO fix swing (see loop below)
  params:add_group("Clock",2)
  params:add_number("div","div",1,16,4,function(param) return param:get() end,false)
  params:set_action("div", function(n) div = n end)
  div = params:get("div")
  -- -- TODO add clock tempo control here for easy access
  swing_spec = controlspec.def{
    min=0.00,
    max=100.0,
    warp='lin',
    step=1,
    default=50,
    quantum=0.01,
    wrap=false,
    units='%'
  }
  params:add_control("swing","swing",swing_spec)
  params:set_action("swing", function(n) swing = n end)
  swing = params:get("swing")

  params:add_separator("Output")
  params:add_group("PolyPerc",3)
  local pp_cutoff_spec = controlspec.FREQ
  pp_cutoff_spec.default = 1000
  params:add_control("pp_cutoff","cutoff",pp_cutoff_spec)
  params:set_action("pp_cutoff", function(n) engine.cutoff(n) end)
  local pp_pw_spec = controlspec.UNIPOLAR
  pp_pw_spec.default = 0.5
  params:add_control("pp_pw","pw",controlspec.UNIPOLAR)
  params:set_action("pp_pw", function(n) engine.pw(n) end)
  local pp_release_spec = controlspec.UNIPOLAR
  pp_release_spec.default = 0.5
  params:add_control("pp_release","release",controlspec.UNIPOLAR)
  params:set_action("pp_release", function(n) engine.release(n) end)

  -- State vars
  notes = {}
  note_bit_bytes = {
    0x55,
    0x33,
    0xe5,
    0xf0,
  }
  gates = 0x55
  gates_2 = 0x33
  gate_op = "or"

  lock_probs = false
  note_bit_ps = {1,1,1,1}
  gates_2_p = 1
  gates_p = 1
  gate_op_p = 1
  
  tick = 0
  calcd_gates = 0xFF

  -- Left-overs from sequencer
  -- ops = {"xor","and","or","xor"}
  -- ops_seq = s(ops)
  
  -- args = {0x77,0xfc,0x81}
  -- args_seq = s(args)
  
  period = 8
  div = 4
  tick = 0

  on_notes = {}
  last_note = nil
  
  -- TODO add real support for start/stop clock
  sequence = clock.run(
    function()
      clock.sync(4)
      while true do
        tick = tick + 1
        -- tick = math.floor(clock.get_beats()*div)
        bit_num = ((tick - 1) % period) + 1
        gate_op = gate_op -- or seq_op
        local new_calcd_gates
        if prob_mode == 1 then
          -- Update patterns depending on pility setting
          gates = prob_flip_bit(gates,bit_num,gates_p)
          gates_2 = prob_flip_bit(gates_2,bit_num,gates_2_p)
          for i=1,4 do
            note_bit_bytes[i] = prob_flip_bit(note_bit_bytes[i], bit_num, note_bit_ps[i])
          end
          new_calcd_gates = op_fns[gate_op](gates,gates_2)
        elseif prob_mode == 2 then
        -- TODO optimize this so we're not recalculating full byte each time
          new_calcd_gates = op_fns[gate_op](coin_flip(gates_p) and gates or 0,coin_flip(gates_2_p) and gates_2 or 0)
          -- only update current bit
          -- (overwrite that bit in calcd_gates by setting to try then anding with new product)
          calcd_gates = bit8_set_bit(calcd_gates,bit_num, bit8_get_bit(new_calcd_gates,bit_num))
        end
        -- gate op prob always functions the same (unstable ops feels too random)
        local new_bit = bit8_get_bit(coin_flip(gate_op_p) and new_calcd_gates or bit8_bnot(new_calcd_gates),bit_num)
        calcd_gates = bit8_set_bit(calcd_gates,bit_num,new_bit)
        -- get_note_bit_bytes_step includes trigger prob_mode logic
        -- TODO refactor trigger logic out of get_note_bit_bytes_step
        local note = base_note + get_note_bit_bytes_step(bit_num)
        notes[bit_num] = note
        -- TODO add MIDI out option
        if is_bit_set(calcd_gates,bit_num) and scale[note] then
          -- TODO support note offs too
          engine.hz(MusicUtil.note_num_to_freq(scale[note]))
        else
          -- engine.noteOff(0)    
        end
        screen.dirty = true
        redraw()
        -- 50% swing is 100% tick width all the time
        -- TODO handle div ~= 4
        -- See https://github.com/21echoes/cyrene/blob/master/lib/sequencer.lua#L388
        swing_offset = -1 * (1 - swing/100) * 2 /div
        clock.sync(2/div,(tick % 2 == 1) and swing_offset or 0)
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
    if (keys[1] == 1) then
      lock_probs = d > 0
    else
      active_mode = util.clamp(active_mode + d,1,2)
      focus_control = 1
    end
    redraw()
    return
  end
  if active_mode == 1 then
    if e == 2 then
      -- if keys[1] == 1 and keys[2] == 1 then
      --   if focus_control == 1 then
      --     gate_op_stab = util.clamp(gate_op_stab+d/10,0,1)
      --   elseif focus_control == 2 then
      --     gates_stab = util.clamp(gates_stab+d/10,0,1)
      --   elseif focus_control == 3 then
      --     gates_2_stab = util.clamp(gates_2_stab+d/10,0,1)
      --   end
      -- elseif keys[1] == 1 then
      if keys[1] == 1 then
        -- NOTE we invert the appearance of prob, since it's labeled randomness
        d = d * -1
        if focus_control == 1 then
          gate_op_p = util.clamp(gate_op_p+d/10,0,1)
        elseif focus_control == 2 then
          gates_p = util.clamp(gates_p+d/10,0,1)
        elseif focus_control == 3 then
          gates_2_p = util.clamp(gates_2_p+d/10,0,1)
        end
      else
        focus_control= util.clamp(focus_control + d,1,3)
      end
    elseif e == 3 then
      if focus_control == 1 then
        -- if k[1] is down, move gates_2 and gates in op directions
        local inverse = (keys[1] == 1) and -1 or 1 
        gates = bit8_rrot(gates,d)
        gates_2 = bit8_rrot(gates_2,inverse*d)
      else
        if keys[2] == 1 then
          -- inc byte / most significant nibble
          local amt = d * ((keys[1] == 1) and 0x10 or 1)
          if focus_control == 2 then
            gates = util.wrap(gates+amt,0,256)
          else
            gates_2 = util.wrap(gates_2+amt,0,256)
          end
        else
          -- rot / shift
          local enc_op = (keys[1] ~= 1) and bit8_rrot or bit8_rshift
          if focus_control == 2 then
            gates = enc_op(gates,d)
          else
            gates_2 = enc_op(gates_2,d)
          end
        end
      end
    end
  elseif active_mode == 2 then
    if (e==2) then
      -- if keys[2] == 1 and keys[1] == 1 then
      --   note_bit_stabs[focus_control] = util.clamp(note_bit_stabs[focus_control] + d/10,0,1)
      -- elseif keys[1] == 1 then
      if keys[1] == 1 then
        d = d * -1
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
      -- complex gate_op assignment logic here
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
            gates_2 = bit8_bnot(gates_2)
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

-- TODO redo for add screen but simple just vertical scaling of steps
function draw_bin(num,bits,x,y,w,h,focus,on_h_ratio,on_w_ratio)
  on_h_ratio = on_h_ratio ~= nil and on_h_ratio or 1
  on_w_ratio = on_w_ratio ~= nil and on_w_ratio or 1
  local xd = w/bits
  -- screen.level(level)
  -- screen.rect(x,y,w,h)
  -- screen.stroke()
  for j=1,bits do
    local i = bits - (j - 1)
    -- local do_highlight = (8 - (tick - 1) % 8) == i
    local do_highlight = (1 + (tick - 1) % 8) == j
    local value = bit8_get_bit(num,j)
    screen.blend_mode(2)
    -- draw background
    -- screen.level(do_highlight and 3 or 1)
    -- screen.rect(x+(i-1)*xd,y,xd,h)
    -- screen.fill()
    -- if on or stability mode, draw prob overlay
    if value ~= 0 or prob_mode == 1 then
      screen.level(value ~= 0 and 4 or 2)
      screen.rect(x+(i-1)*xd,y + h * (1 - on_h_ratio),xd,h * on_h_ratio)
      screen.fill()
    end
    -- if on, draw status overlay
    if value ~= 0 then
      screen.level(8)
      screen.rect(x+(i-1)*xd,y,xd,h)
      -- screen.rect(x+(i-1)*xd,y + h * (1 - on_h_ratio),xd,h * on_h_ratio)
      screen.fill()
    end
    -- draw highlight overlay
    if do_highlight then
      screen.level(3)
      screen.rect(x+(i-1)*xd,y,xd,h)
      screen.fill()
    end
    -- draw focus overlay
    if focus then
      screen.level(15)
      screen.rect(x,y,w,h)
      screen.stroke()
    end
    screen.blend_mode(1)
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
    -- Box around op
    local op_text_width = screen.text_extents(gate_op or "--")
    if focus_control == 1 then
      local box_w = op_text_width + 12
      screen.rect((128-box_w)/2,8,box_w,18)
      screen.level(1)
      screen.fill()
      screen.level(13)
      screen.rect((128-box_w)/2,8,box_w,18)
      screen.stroke()
    end
    screen.move(64,24)
    local op_level = focus_control == 1 and 10 or 2 
    screen.level(op_level)
    screen.text_center(gate_op or "--")
    screen.move(64-math.floor(op_text_width/2)-6,24)
    screen.level(math.ceil(op_level * (1-gate_op_p)))
    screen.blend_mode(8)
    screen.text("!")
    screen.blend_mode(1)
    -- screen.move(128,24)
    -- screen.text_right(hexfmt(gates_2))
    screen.font_size(8) ---------- set the size to 8
    -- screen.move(4,64)
    -- screen.text(tick or "--")
    -- screen.move(4, 7) ---------- move the pointer to x = 64, y = 32
    -- screen.text(message) 
    -- screen.fill() ---------------- fill the termini and message at once
    -- NOTE we display probability as "randomness", so as inverse
    draw_bin(gates,8,10,28,106,period,focus_control == 2,1-gates_p)
    draw_bin(gates_2,8,10,36,106,period,focus_control == 3,1-gates_2_p)
    screen.level(15)
  elseif (active_mode == 2) then
    -- TODO add hex totals for each step
    screen.font_face(1) ---------- set the font face to "04B_03"
    screen.font_size(8) ---------- set the size to 8
    for i=1,4 do
      screen.level((focus_control == i) and 15 or 4)
      screen.move(1,i*10)
      screen.text(params:get("interval_"..i))
      draw_bin(note_bit_bytes[i],8,10,i*10-5,106,period,focus_control == i,1-note_bit_ps[i],1)
    end
  end
  for i=1,8 do
    screen.move(16+((i-1)*106/8),52)
    screen.level(8 - ((tick - 1) % 8) == i and 15 or 2)
    screen.text_center(notes[9-i] and scale[notes[9-i]] and MusicUtil.note_num_to_name(scale[notes[9-i]]) or "")
    screen.fill()
  end
  -- TODO fix calcd gates
  draw_bin(calcd_gates,8,10,54,106,period,true,0,0)
  if lock_probs then
    screen.fill(15)
    screen.rect(1,1,126,62)
    screen.stroke()
  end
  screen.update() -------------- update space
end


function r() ----------------------------- execute r() in the repl to quickly rerun this script
  norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end