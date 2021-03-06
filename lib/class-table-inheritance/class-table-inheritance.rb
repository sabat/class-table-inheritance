# ClassTableInheritance is an ActiveRecord plugin designed to allow 
# simple multiple table (class) inheritance.

module ActiveRecord
  class Base  
    attr_reader :reflection
    cattr_accessor :association_id

    class << self
      def association_class
        @association_class ||= Kernel.const_get(association_id.to_s.camelize)
      end

      def inherited_column_names
        # Get the columns of association class.
        inherited_column_names = association_class.column_names
    
        # Make a filter in association columns to exclude the columns that
        # the generalized class already have.
        inherited_column_names.reject { |c| self.column_names.grep(c).length > 0 || %w{ type subtype }.include?(c) }
      end

      def inherited_method_names
        # Get the methods of the association class and turn it to an Array of Strings.
        inherited_method_names = association_class.reflections.map { |key,value| key.to_s }
    
        # Exclude the methods that the general class already has.
        inherited_method_names.reject { |c| self.reflections.map {|key, value| key.to_s }.include?(c) }
      end

      def inherited_columns
        association_class.columns
      end
  
      def acts_as_superclass
        if self.column_names.include?("subtype")
          @@acts_as_superclass = true
          def self.find(*args)
            super_classes = super.kind_of?(Array) ? super : [super]
            begin
              super_classes.map do |superclass|
                if superclass.subtype
                  inherits_type = superclass.subtype.to_s.classify.constantize
                  inherits_type.send(:find, superclass.id)
                else
                  super_classes
                end
              end
            rescue
              super_classes
            end
          end
        end  
      end

    end # class << self
    
    def self.inherits_from(assoc_id)
      self.association_id = assoc_id
      @inherits = true

      # add an association, and set the foreign key.
      has_one association_id, :class_name => association_id.to_s.camelize, :foreign_key => :id, :dependent => :destroy
  
      # set the primary key. It's needed because the generalized table doesn't have a field ID.
      self.primary_key = "#{association_id}_id"
  
      # Autobuild method to make a instance of association
      define_method("#{association_id}_with_autobuild") do
        send("#{association_id}_without_autobuild") || send("build_#{association_id}")
      end
  
      # Set a method chain with autobuild.
      alias_method_chain association_id, :autobuild    
    
      # bind the before save. This method calls the save of association, and
      # gets our generated ID, and sets the association_id field.
      before_save :save_inherit
    
      # Bind the validation of association.
      validate :inherit_association_must_be_valid    
  
      # Generate a method to validate the field of association.    
      define_method("inherit_association_must_be_valid") do
        association = send(association_id)
  
        unless valid = association.valid?
          association.errors.each do |attr, message|
            errors.add(attr, message)
          end
        end
      
        valid
      end    

      # create the proxy methods to get and set the properties and methods
      # in association class.
      (inherited_method_names + inherited_column_names).each do |name|
        define_method name do
          # if the field is ID than i only bind that with the association field.
          # this is needed to bypass the overflow problem when the ActiveRecord
          # try to get the id to find the association.
          if name == 'id'
            self["#{association_id}_id"]
          else
            assoc = send(association_id)
            assoc.send(name)
          end
        end

        define_method "#{name}=" do |new_value|
          # if the field is 'id' then I only bind that with the association field.
          # this is needed to bypass the overflow problem when the ActiveRecord
          # try to get the id to find the association.
          if name == 'id'
            self["#{association_id}_id"] = new_value
          else       
            assoc = send(association_id)
            assoc.send("#{name}=", new_value)
          end
        end
      end
  
      # Create a method do bind in before_save callback, this method
      # only call the save of association class and set the id in the
      # generalized class.
      define_method("save_inherit") do |*args|
        association = send(association_id)
        if association.attribute_names.include?("subtype")
          association.subtype = self.class.to_s
        end
        association.save
        self["#{association_id}_id"] = association.id
        true
      end

      class << self
        alias :orig_columns :columns
      end

      define_singleton_method("columns") do
        orig_columns + inherited_columns
      end

      class << self
        alias :orig_column_names :column_names
      end

      define_singleton_method("column_names") do
        self.columns.collect { |c| c.name }
      end
  
      class << self
        alias :orig_inspect :inspect
      end
  
      define_singleton_method("inspect") do
        if table_exists?
          attrs = Hash[ *columns.collect { |c| [ c.name, c.type ] }.flatten ]
          attr_list = attrs.map { |k,v| "#{k}: #{v}" } * ', '
          "#{self.name}(#{attr_list})"
        else
          "#{self.name}(Table doesn't exist)"
        end
      end

      alias :orig_inspect :inspect

      define_method("inspect") do
        if inherits?
          inspection =
              if attributes
                column_names = self.class.inherited_column_names + self.class.column_names
                column_names.collect { |name| "#{name}: #{attribute_for_inspect(name)}" if has_attribute?(name) }.compact.join(', ')
              else
                'not initialized'
              end
          "#<#{self.class} #{inspection}>"
        else
          orig_inspect
        end
      end

      define_method("association_id") do
        self.class.association_id
      end

      alias :orig_has_attribute? :has_attribute?

      define_method("has_attribute?") do |name|
        name = name.to_s
        orig_has_attribute?(name) || attributes.has_key?(name)
      end

      define_method("inherited_attributes") do
        Hash[ self.class.inherited_column_names.map { |c| [ c, self[c.to_sym] ] } ]
      end

      alias :orig_read_attribute :read_attribute

      define_method("read_attribute") do |attr_name|
        # Monkey-patching ActiveRecord this much is really
        # not a good idea, but I don't see a lot of choice.
        # By doing this, we're losing the type-casting that
        # AR does, but that is not a huge loss.
        #
        # self.send(attr_name.to_sym)

        attr_name = attr_name.to_sym
        if self.has_attribute? attr_name
          self.orig_read_attribute attr_name
        elsif association_class.has_attribute?(attr_name)
          association_class.read_attribute attr_name
        end
      end

      alias :orig_attributes :attributes

      define_method("attributes") do
        orig_attributes.merge( inherited_attributes )
      end

      alias :orig_attribute_names :attribute_names

      define_method("attribute_names") do
        self.class.inherited_column_names + self.class.column_names
      end
  
    end # inherits_from

    def self.acts_as_superclass?
      @@acts_as_superclass
    end
    
    def self.inherits?
      @inherits
    end

    def acts_as_superclass?
      self.class.acts_as_superclass?
    end
  
    def inherits?
      self.class.inherits?
    end

    def inherited_attribute_names
      self.class.inherited_column_names
    end

    def association_class
      self.class.association_class
    end

    alias :inherited_column_names :inherited_attribute_names

  end
end
