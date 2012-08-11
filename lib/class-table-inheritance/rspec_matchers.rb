require 'rspec'

RSpec::Matchers.define :act_as_superclass do
  match do |klass|
    klass.respond_to?(:acts_as_superclass?) and klass.acts_as_superclass?
  end
end

RSpec::Matchers.define :inherit_from do |expected_parent_class|
  match do |klass|
    klass.respond_to?(:association_id) and expected_parent_class == klass.association_id
  end

  failure_message_for_should do |model|
    "expected to inherit from #{expected_parent_class}"
  end
end

