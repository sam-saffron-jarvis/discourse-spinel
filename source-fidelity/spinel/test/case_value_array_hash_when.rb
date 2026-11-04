# A `case` used as a value, with an Array or Hash subject and an Array or
# Hash arm, compares by value: Array#=== and Hash#=== are Object#===, which
# is ==. On c24731a1 the statement form was right, but the value form fell
# to a pointer compare and took the else arm on every line below marked
# "value". CRuby answers every line as printed in the .expected.
def pair; [1, 2]; end
def opts; {a: 1}; end

r = case pair
    when [1, 2] then :onetwo
    else :none
    end
p [:value_array, r]

r = case opts
    when {a: 1} then :a
    else :none
    end
p [:value_hash, r]

x = [1, 2]
p [:expr_local, (case x when [1, 2] then :yes else :no end)]
p [:expr_call_arm, (case x when pair then :yes else :no end)]
p [:expr_second_alt, (case x when [3], [1, 2] then :yes else :no end)]
p [:expr_nested, (case [1, [2, 3]] when [1, [2, 3]] then :yes else :no end)]
p [:expr_strings, (case %w[a b] when ["a", "b"] then :yes else :no end)]
p [:expr_string_keys, (case({"k" => 1}) when {"k" => 1} then :yes else :no end)]
p [:expr_longer_arm, (case x when [1, 2, 3] then :longer when [1] then :shorter else :neither end)]
p [:expr_fresh, (case (x * 1) when [1, 2] then :yes else :no end)]

# an arm no Array can equal runs for its effects and answers false
n = 0
p [:expr_other_kind, (case x when (n += 1; "s") then :str when [1, 2] then :arr else :no end), n]

# a poly-array subject takes the same arm
def mixed; [1, "a"]; end
p [:expr_poly, (case mixed when [1, "a"] then :yes else :no end)]

# the statement form, unchanged
case x
when [1, 2] then p [:stmt, :yes]
else p [:stmt, :no]
end
