; Stops the Win key from opening the Start menu on release, so GlazeWM's
; Win+<key> shortcuts never pop it up by accident. Win+<key> combos still work.
; The Start menu stays reachable from the logo on the bar (or Ctrl+Esc).
; How: while Win is held, send the unassigned key vkE8 so Windows sees a
; "Win+something" combo instead of a lone Win press.

~LWin:: Send("{Blind}{vkE8}")
~RWin:: Send("{Blind}{vkE8}")
