BITWISE

A probablistic bitwise sequencer
intended for live play.

UI is split into two pages: 
GATES and NOTES

ALL PAGES
* k1: exit
* e1: select page
* [+ k1]: Lock random
* e2: select control
* [+ k1]: Set randomness
* [+ k1 k2]: TBD

GATES PAGE controls
* OPERATOR:
  * k2 [+ k1]: and [nand]
  * k3 [+ k1]: or [xor]
  * e3: l/r rotate both
  * [+ k1]:[oposite directions]
* GATE BYTE:
  * k3 [+ k1]: not [reflect TODO] 
  * e3: l/r rotate
  * [+ k1]: l/r shift
  * [+ k2]: +/- value
  * [+ k1 k2]: +/- upper nibble

NOTES PAGE controls
* Each BIT SEQUENCE BYTE
  * k2 [+ k1]: not [momentary] 
  * k3 [ + k1]: reflect [momentary]
  * e3: l/r rotate
  * [+ k1]: l/r shift
  * [+ k2]: +/- value
  * [+ k1 k2]: +/- upper nibble
