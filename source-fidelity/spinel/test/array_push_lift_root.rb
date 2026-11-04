# The push, << and append arm for an array receiver has a literal-lift form:
# a typed array literal pushed an element of another type is rebuilt as a
# fresh poly array, the literal's elements and the arguments are boxed and
# pushed into it, and the array is the value. The fresh array was held by
# nothing while those elements and arguments ran, so one that allocates
# could free it. On 14ec1cd7 the loops below count wrong results under
# SPINEL_GC_STRESS=1 and two of them in a plain build. With the array
# rooted they print eight zeros and the values CRuby prints.
def churn
  (1..60).map { |i| [i, "s#{i}"] }
  (1..30).map { |i| "t#{i}" }
  (1..30).map { |i| i * 3 }
  nil
end

def ints = (1..40).map { |i| i * 10 }

def lifted(n) = [n, 2].push((churn; "x"))

bad = [0, 0, 0, 0, 0, 0, 0, 0]
200.times do
  bad[0] += 1 if [1, 2].push((churn; "x")).length != 3
  bad[1] += 1 if [ints.first, 2].push((churn; "y"), (churn; "z")).length != 4
  bad[2] += 1 if ([1.5, 2.5] << (churn; "f")).length != 3
  bad[3] += 1 if ["a", "b"].append((churn; 7)).length != 3
  bad[4] += 1 if [(churn; 1), 2].push("x").length != 3
  r = [1, 2].push((churn; "x"))
  bad[5] += 1 if r[0] != 1 || r[1] != 2 || r[2] != "x"
  bad[6] += 1 if lifted(5).length != 3
  bad[7] += 1 if [3].map { |i| [i, 4].push((churn; "m")).length } != [3]
end
p bad

p [1, 2].push((churn; "x"))
p [ints.first, 2].push((churn; "y"), (churn; "z"))
p [1.5, 2.5] << (churn; "f")
p ["a", "b"].append((churn; 7))
p [(churn; 1), 2].push("x")
p lifted(5)
