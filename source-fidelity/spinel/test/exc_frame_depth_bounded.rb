# The exception-frame stack is fixed at 64, and the depth that fills it is
# dynamic, not lexical: this method's begin frame stays armed across the
# recursive call it makes, so level 65 would arm a 65th frame. Spinel stops
# there with CRuby's "stack level too deep (SystemStackError)" on stderr and
# exits 1; CRuby's own stack is far deeper than this and runs to the end.
# Neither prints anything, which is what lets the suite hold this: the
# CRuby-generated .expected is empty and stays empty, the exit status is not
# compared, and the .err.expected sidecar pins the message.
def deep_begin(n)
  begin
    return 0 if n <= 0
    deep_begin(n - 1) + 1
  rescue ZeroDivisionError
    -1
  end
end
deep_begin(70)

# CRuby runs this to the end; Spinel stops above, at its handler-stack bound,
# with the fatal on stderr. The non-zero CRuby exit keeps regen off both files.
exit 1
