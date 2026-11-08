# frozen_string_literal: true
# UNIT-only caller of the generated original/shared writable login DSL. Source
# methods are supplied by the Python test, never manually recreated here.
[ReferencePolicyParent, SharedPolicyParent].each do |parent|
  raise "initial policy was not nil" unless parent.requires_login_arg.nil?
  parent.requires_login(only: [:latest])
  raise "writable policy lost" unless parent.requires_login_arg == {only: [:latest]}
end
raise "class-instance policy incorrectly inherited" unless ReferencePolicyChild.requires_login_arg.nil? && SharedPolicyChild.requires_login_arg.nil?
ReferencePolicyChild.requires_login(except: [:latest])
SharedPolicyChild.requires_login(except: [:latest])
raise "child rule mismatch" unless ReferencePolicyChild.requires_login_arg == SharedPolicyChild.requires_login_arg
raise "child overwrote parent" unless ReferencePolicyParent.requires_login_arg == SharedPolicyParent.requires_login_arg && SharedPolicyParent.requires_login_arg == {only: [:latest]}
raise "sibling inherited rule" unless ReferencePolicySibling.requires_login_arg.nil? && SharedPolicySibling.requires_login_arg.nil?
ReferencePolicyChild.requires_login
SharedPolicyChild.requires_login
raise "empty required policy lost" unless ReferencePolicyChild.requires_login_arg == {} && SharedPolicyChild.requires_login_arg == {}
puts "PASS original/shared per-class writable requires_login policy, child/sibling isolation and empty required rule"
