# A true or false held as a plain boolean, tested against TrueClass and
# FalseClass by the case/in pattern forms. On ec604b80 the first nine lines
# print the no-match answer (neither, neither, none, other, none, unguarded,
# false, statement none, other); the last two already print what the
# .expected holds.
t = 3 > 2
f = 3 < 2

def which(v)
  case v
  in TrueClass then "true"
  in FalseClass then "false"
  else "neither"
  end
end

puts which(t), which(f)
puts(case t; in FalseClass then "false"; in TrueClass then "true"; else "none"; end)
puts(case f; in TrueClass | FalseClass then "bool"; else "other"; end)
puts(case t; in TrueClass => x then "bound #{x}"; else "none"; end)
puts(case f; in FalseClass if !f then "guarded"; else "unguarded"; end)
puts((t in TrueClass))
case f
in TrueClass then puts "statement true"
in FalseClass then puts "statement false"
else puts "statement none"
end
puts(case f; in Integer | FalseClass then "alternation"; else "other"; end)
puts((f in TrueClass))
puts(case t; in Integer then "integer"; in Object then "object"; end)
