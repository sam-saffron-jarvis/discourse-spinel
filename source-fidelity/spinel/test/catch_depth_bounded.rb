# The same bound on the catch stack, reached the same dynamic way: each level
# holds its catch open across the recursive call, so level 65 would push a 65th
# entry. Spinel stops with CRuby's "stack level too deep (SystemStackError)"
# and exits 1; CRuby runs to the end. Silent on stdout either way -- see
# test/exc_frame_depth_bounded.rb for why that is what the suite can hold.
def deep_catch(n)
  return 0 if n <= 0
  catch(:t) { deep_catch(n - 1) + 1 }
end
deep_catch(70)

# CRuby runs this to the end; Spinel stops above, at its handler-stack bound,
# with the fatal on stderr. The non-zero CRuby exit keeps regen off both files.
exit 1
