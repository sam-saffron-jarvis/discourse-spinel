# A typed row zipped with a row that is only an array at run time (an element
# of a poly table walked by each_with_index). The block params stay Float,
# the receiver's element type; the poly row's elements arrive boxed. Writing
# that box straight into the Float param did not compile.

def dot(ai, rows)
  total = 0.0
  rows.each_with_index do |tj, j|
    s = 0.0
    ai.zip(tj) do |av, tv|
      s += av * tv
    end
    total += s
  end
  total
end

ai = [1.0, 2.0, 3.0]
rows = []
rows << [4.0, 5.0, 6.0]
rows << [0.5, 0.5, 0.5]
puts dot(ai, rows)
