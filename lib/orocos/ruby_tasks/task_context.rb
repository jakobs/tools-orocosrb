module Orocos
    module RubyTasks

    # A TaskContext that lives inside this Ruby process
    #
    # For now, it has very limited functionality: mainly managing ports
    class TaskContext < Orocos::TaskContext
        # Internal handler used to represent the local RTT::TaskContext object
        #
        # It is created from Ruby as it handles the RTT::TaskContext pointer
        class LocalTaskContext
            # [Orocos::TaskContext] the remote task
            attr_reader :remote_task
            # [String] the task name
            attr_reader :name

            def initialize(name)
                @name = name
            end
        end

        # Creates a new local task context that fits the given oroGen model
        #
        # @return [TaskContext]
        def self.from_orogen_model(name, orogen_model)
            new(name, :model => orogen_model)
        end

        # Creates a new ruby task context with the given name
        #
        # @param [String] name the task name
        # @return [TaskContext]
        def self.new(name, options = Hash.new, &block)
            options, _ = Kernel.filter_options options, :model

            if block && !options[:model]
                model = Orocos::Spec::TaskContext.new(Orocos.master_project, name)
                model.instance_eval(&block)
                options[:model] = model
            end

            local_task = LocalTaskContext.new(name)
            if options[:model] && options[:model].name
                local_task.model_name = options[:model].name
            end

            remote_task = super(local_task.ior, options)
            local_task.instance_variable_set :@remote_task, remote_task
            remote_task.instance_variable_set :@local_task, local_task

            if options[:model]
                remote_task.setup_from_orogen_model(options[:model])
            end
            remote_task
        end

        def initialize(ior, options = Hash.new)
            @local_ports = Hash.new
            @local_properties = Hash.new
            options, other_options = Kernel.filter_options options, :name => name
            super(ior, other_options.merge(options))
        end

        # Create a new input port on this task context
        #
        # @param [String] name the port name. It must be unique among all port
        #   types
        # @param [String] orocos_type_name the name of the port's type, as
        #   recognized by Orocos. In most cases, it is the same than the
        #   typelib type name
        # @option options [Boolean] :permanent if true (the default), the port
        #   will be stored permanently on the task. Otherwise, it will be
        #   removed as soon as the port object gets garbage collected by Ruby
        # @option options [Class] :class the class that should be used to
        #   represent the port on the Ruby side. Do not change unless you know
        #   what you are doing
        def create_input_port(name, orocos_type_name, options = Hash.new)
            options, other_options = Kernel.filter_options options, :class => LocalInputPort
            create_port(false, options[:class], name, orocos_type_name, other_options)
        end

        # Create a new output port on this task context
        #
        # @param [String] name the port name. It must be unique among all port
        #   types
        # @param [String] orocos_type_name the name of the port's type, as
        #   recognized by Orocos. In most cases, it is the same than the
        #   typelib type name
        # @option options [Boolean] :permanent if true (the default), the port
        #   will be stored permanently on the task. Otherwise, it will be
        #   removed as soon as the port object gets garbage collected by Ruby
        # @option options [Class] :class the class that should be used to
        #   represent the port on the Ruby side. Do not change unless you know
        #   what you are doing
        def create_output_port(name, orocos_type_name, options = Hash.new)
            options, other_options = Kernel.filter_options options, :class => LocalOutputPort
            create_port(true, options[:class], name, orocos_type_name, other_options)
        end

        # Remove the given port from this task's interface
        #
        # @param [LocalInputPort,LocalOutputPort] port the port to be removed
        # @return [void]
        def remove_port(port)
            @local_ports.delete(port.name)
            port.disconnect_all # don't wait for the port to be garbage collected by Ruby
            @local_task.do_remove_port(port.name)
        end

        # Deregisters this task context.
        #
        # This is done automatically when the object is garbage collected.
        # However, it is sometimes better to do this explicitely, for instance
        # to avoid the name clash warning.
        def dispose
            @local_task.dispose
        end

        # Creates a new property on this task context
        #
        # @param [String] name the property name
        # @param [Model<Typelib::Type>,String] type the type or type name
        # @return [Property] the property object
        def create_property(name, type)
            orocos_type_name = Orocos.find_orocos_type_name_by_type(type)
            Orocos.load_typekit_for orocos_type_name
            local_property = @local_task.do_create_property(Property, name, orocos_type_name)
            @local_properties[local_property.name] = local_property
            @properties[local_property.name] = local_property
            local_property
        end

        # Sets up the interface of this task context so that it matches the
        # given oroGen model
        #
        # @param [Orocos::Spec::TaskContext] orogen_model the oroGen model
        # @return [void]
        def setup_from_orogen_model(orogen_model)
            new_properties, new_outputs, new_inputs = [], [], []
            remove_outputs, remove_inputs = [], []

            orogen_model.each_property do |p|
                if has_property?(p.name)
                    if property(p.name).orocos_type_name != p.orocos_type_name
                        raise IncompatibleInterface, "cannot adapt the interface of #{self} to match the model in #{orogen_model}: #{self} already has a property called #{p.name}, but with a different type"
                    end
                else new_properties << p
                end
            end
            orogen_model.each_input_port do |p|
                if has_port?(p.name)
                    if port(p.name).orocos_type_name != p.orocos_type_name
                        remove_inputs << p
                        new_inputs << p
                    end
                else new_inputs << p
                end
            end
            orogen_model.each_output_port do |p|
                if has_port?(p.name)
                    if port(p.name).orocos_type_name != p.orocos_type_name
                        remove_outputs << p
                        new_outputs << p
                    end
                else new_outputs << p
                end
            end

            remove_inputs.each { |p| remove_input_port p }
            remove_outputs.each { |p| remove_output_port p }
            new_properties.each do |p|
                create_property(p.name, p.orocos_type_name)
            end
            new_inputs.each do |p|
                create_input_port(p.name, p.orocos_type_name)
            end
            new_outputs.each do |p|
                create_output_port(p.name, p.orocos_type_name)
            end
            @model = orogen_model
            nil
        end

        private

        # Helper method for create_input_port and create_output_port
        def create_port(is_output, klass, name, type, options)
            # Load the typekit, but no need to check on it being exported since
            # #find_orocos_type_name_by_type will do it for us
            Orocos.load_typekit_for(type, false)
            orocos_type_name = Orocos.find_orocos_type_name_by_type(type)
            Orocos.load_typekit_for(orocos_type_name, true)

            options = Kernel.validate_options options, :permanent => true
            local_port = @local_task.do_create_port(is_output, klass, name, orocos_type_name)
            if options[:permanent]
                @local_ports[local_port.name] = local_port
                @ports[local_port.name] = local_port
            end
            local_port
        end
    end
    end
end
