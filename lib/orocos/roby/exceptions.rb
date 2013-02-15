module Orocos
    module RobyPlugin
        class InternalError < RuntimeError; end
        class ConfigError < RuntimeError; end
        class SpecError < RuntimeError; end

        class Ambiguous < SpecError; end

        class InvalidPortMapping < SpecError; end

        # Raised when a provides declaration does not match the underlying task
        # interface
        class InvalidProvides < SpecError
            attr_reader :original_error
            attr_reader :model
            attr_reader :required_service

            def initialize(model, required_service, original_error = nil)
                @model = model
                @required_service = required_service
                @original_error   = original_error
                super()
            end

            def pretty_print(pp)
                pp.text "#{model.short_name} does not provide the '#{required_service.short_name}' service's interface"
                if original_error
                    pp.nest(2) do
                        pp.breakable
                        pp.text original_error.message
                    end
                end
            end
        end

        # Exception raised during instanciation if there is an ambiguity for a
        # composition child
        class AmbiguousIndirectCompositionSelection < Ambiguous
            attr_reader :composition_model
            attr_reader :child_name
            attr_reader :selection
            attr_reader :candidates

            def initialize(composition_model, child_name, selection, candidates)
                @composition_model = composition_model
                @child_name = child_name
                @selection  = selection
                @candidates = candidates
            end

            def pretty_print(pp)
                pp.text "ambiguity while searching for compositions for the child #{child_name} of #{composition_model.short_name}"
                pp.breakable
                pp.text "selection is:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(selection) do |keyvalue|
                        name, model = keyvalue
                        pp.text "#{name} => #{model.short_name}"
                    end
                end
                pp.breakable
                pp.text "which corresponds to the following compositions:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(candidates) do |model|
                        pp.text "#{model.short_name}"
                    end
                end
            end
        end

        # Exception raised when a service is required but none can be found on a
        # particular task context
        class NoMatchingService < Ambiguous
            attr_reader :task_model
            attr_reader :required_service

            def initialize(task_model, required_service)
                @task_model, @required_service =
                    [*task_model], required_service
            end

            def pretty_print(pp)
                name = task_model.map(&:short_name).join(", ")
                candidates = task_model.inject([]) { |set, m| set.concat(m.each_data_service.to_a) }
                pp.text "there are no services in #{name} that provide the service #{required_service}"
                pp.breakable
                pp.text "the services of #{name} are:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(candidates) do |srv|
                        _, srv = *srv
                        pp.text "#{srv.full_name}: #{srv.model.short_name}"
                    end
                end
            end
        end

        class UnknownServiceName < SpecError
            attr_reader :component_model
            attr_reader :service_name

            def initialize(component_model, service_name)
                @component_model, @service_name = component_model, service_name
            end

            def pretty_print(pp)
                pp.text "cannot find service #{service_name} in #{component_model.short_name}"
                pp.text "the services of #{component_model.short_name} are:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(component_model.each_data_service.to_a) do |srv|
                        _, srv = *srv
                        pp.text "#{srv.full_name}: #{srv.model.short_name}"
                    end
                end
            end
        end


        # Refinement of NoMatchingService for a composition child. It adds the
        # information of the composition / child name
        class NoMatchingServiceForCompositionChild < NoMatchingService
            attr_reader :composition_model
            attr_reader :child_name

            def initialize(composition_model, child_name, task_model, required_service)
                @composition_model, @child_name = composition_model, child_name
                super(task_model, required_service)
            end

            def pretty_print(pp)
                pp.text "while trying to fullfill the constraints on the child #{child_name} of #{composition_model.short_name}"
                pp.breakable
                super
            end
        end

        # Exception raised when a service is being selected by type, but
        # multiple services are available within the component that match the
        # constraints
        class AmbiguousServiceSelection < Ambiguous
            attr_reader :task_model
            attr_reader :required_service
            attr_reader :candidates

            def initialize(task_model, required_service, candidates)
                @task_model, @required_service, @candidates =
                    task_model, required_service, candidates
            end

            def pretty_print(pp)
                pp.text "there is an ambiguity while looking for a service of type #{required_service} in #{task_model.short_name}"
                pp.breakable
                pp.text "candidates are:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(candidates) do |service|
                        pp.text service.full_name
                    end
                end
            end
        end

        # Exception raised in composition instanciations if a selected component
        # model provides multipe services that fullfills a child's model 
        class AmbiguousServiceMapping < AmbiguousServiceSelection
            attr_reader :composition_model
            attr_reader :child_name

            def initialize(composition_model, child_name, task_model, required_service, candidates)
                super(task_model, required_service, candidates)
                @composition_model, @child_name =
                    composition_model, child_name
            end

            def pretty_print(pp)
                pp.text "while trying to fullfill the constraints on the child #{child_name} of #{composition_model.short_name}"
                pp.breakable
                super
            end
        end

        # Exception raised during the merge steps, if a merge is possible (i.e.
        # a task provides the required service), but ambiguous
        class AmbiguousImplicitServiceSelection < AmbiguousServiceSelection
            attr_reader :task
            attr_reader :merged_task
            attr_reader :compositions

            def initialize(task, merged_task, required_service, candidates)
                super(task.model, required_service, candidates)

                @task = task
                @merged_task = merged_task
                @compositions = merged_task.parent_objects(Roby::TaskStructure::Dependency).
                    map { |parent| [parent, parent[merged_task, Roby::TaskStructure::Dependency].dup] }
            end

            def pretty_print(pp)
                pp.text "error while trying to use #{task} instead of #{merged_task}"
                pp.breakable
                pp.text "#{merged_task} is part of the following compositions:"
                pp.nest(2) do
                    pp.seplist(compositions) do |parent|
                        parent_task, dependency_options = *parent
                        pp.breakable
                        pp.text "child #{dependency_options[:roles].to_a.join(", ")} of #{parent_task}"
                    end
                end
                pp.breakable
                super
            end
        end

        # Exception raised when multiple selections are valid candidates for the
        # same task/service
        class AmbiguousExplicitSelection < Ambiguous
            attr_reader :composition
            attr_reader :child_name
            attr_reader :candidates

            def initialize(composition, child_name, candidates)
                @composition = composition
                @child_name = child_name
                @candidates = candidates
            end

            def pretty_print(pp)
                pp.text "multiple selections apply when selecting the child #{child_name} of #{composition.short_name}"
                pp.breakable
                pp.text "the required model(s) are: #{composition.find_child(child_name).models.map(&:short_name).join(", ")}"
                pp.breakable
                pp.text "candidates:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(candidates) do |sel|
                        if sel.respond_to?(:short_name)
                            pp.text sel.short_name
                        else
                            pp.text sel.to_s
                        end
                    end
                end
            end
        end

        # Exception raised when we could not find concrete implementations for
        # abstract tasks that are in the plan
        class TaskAllocationFailed < SpecError
            # A task to [parents, candidates] mapping for the failed allocations
            attr_reader :abstract_tasks

            # Creates a new TaskAllocationFailed exception for the given tasks.
            #
            # +tasks+ is a mapping from the abstract tasks to the possible
            # candidate implementation for these tasks, i.e.
            #
            #    t => [model0, model1, ...]
            #
            def initialize(tasks)
                @abstract_tasks = Hash.new

                tasks.each do |abstract_task, candidates|
                    parents = abstract_task.
                        enum_for(:each_parent_object, Roby::TaskStructure::Dependency).
                        map do |parent_task|
                            options = parent_task[abstract_task,
                                Roby::TaskStructure::Dependency]
                            [options[:roles], parent_task]
                        end
                    abstract_tasks[abstract_task] = [parents, candidates]
                end
            end

            def pretty_print(pp)
                pp.text "cannot find a concrete implementation for #{abstract_tasks.size} task(s)"

                abstract_tasks.each do |task, (parents, candidates)|
                    pp.breakable
                    pp.text "#{task.to_s.gsub(/Orocos::RobyPlugin::/, '')}"
                    pp.nest(2) do
                        pp.breakable
                        if candidates
                            if candidates.empty?
                                pp.text "no candidates"
                            else
                                pp.text "#{candidates.size} candidates"
                                pp.nest(2) do
                                    pp.breakable
                                    pp.seplist(candidates) do |c_task|
                                        pp.text "#{c_task.short_name}"
                                    end
                                end
                            end
                        end
                        pp.breakable
                        pp.seplist(parents) do |parent|
                            role, parent = parent
                            pp.text "child #{role.to_a.first} of #{parent.to_s.gsub(/Orocos::RobyPlugin::/, '')}"
                        end
                    end
                end
            end
        end

        # Exception raised when we could not find devices to allocate for tasks
        # that are device drivers
        class DeviceAllocationFailed < SpecError
            # The set of tasks that failed allocation
            attr_reader :failed_tasks
            # A task to parents mapping for tasks involved in this error, at the
            # time of the exception creation
            attr_reader :task_parents
            # Existing candidates for this device
            attr_reader :candidates

            def initialize(engine, tasks)
                @failed_tasks = tasks.dup
                @candidates = Hash.new
                @task_parents = Hash.new


                tasks.each do |abstract_task|
                    resolve_device_task(engine, abstract_task)
                end
            end

            def resolve_device_task(engine, abstract_task)
                all_tasks = [abstract_task].to_value_set

                # List the possible candidates for the missing devices
                candidates = Hash.new
                abstract_task.model.each_master_device do |srv|
                    if !abstract_task.arguments["#{srv.name}_name"]
                        candidates[srv] = engine.plan.find_local_tasks(srv.model).to_value_set
                        candidates[srv].delete(abstract_task)
                        all_tasks |= candidates[srv]
                    end
                end
                self.candidates[abstract_task] = candidates

                all_tasks.each do |t|
                    next if task_parents.has_key?(t)

                    parents = t.
                        enum_for(:each_parent_object, Roby::TaskStructure::Dependency).
                        map do |parent_task|
                            options = parent_task[t, Roby::TaskStructure::Dependency]
                            [options[:roles], parent_task]
                        end
                    task_parents[t] = parents
                end
            end

            def pretty_print(pp)
                pp.text "cannot find a device to tie to #{failed_tasks.size} task(s)"

                failed_tasks.each do |task|
                    parents = task_parents[task]
                    candidates = self.candidates[task]

                    pp.breakable
                    pp.text "for #{task.to_s.gsub(/Orocos::RobyPlugin::/, '')}"
                    pp.nest(2) do
                        if !parents.empty?
                            pp.breakable
                            pp.seplist(parents) do |parent|
                                role, parent = parent
                                pp.text "child #{role.to_a.first} of #{parent.to_s.gsub(/Orocos::RobyPlugin::/, '')}"
                            end
                        end

                        pp.breakable
                        pp.seplist(candidates) do |cand|
                            srv, tasks = *cand
                            if tasks.empty?
                                pp.text "no candidates for #{srv.short_name}"
                            else
                                pp.text "candidates for #{srv.short_name}"
                                pp.nest(2) do
                                    pp.breakable
                                    pp.seplist(tasks) do |cand_t|
                                        pp.text "#{cand_t}"
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        # Exception raised at the end of #resolve if some tasks do not have a
        # deployed equivalent
        class MissingDeployments < SpecError
            # The tasks that are not deployed, as a hash from the actual task to
            # a set of [role_set, parent_task] pairs
            #
            # This is computed in #initialize as the dependency structure will
            # probably change afterwards
            attr_reader :tasks

            def initialize(tasks, merge_graph)
                @tasks = Hash.new
                tasks.each do |task|
                    parents = task.
                        enum_for(:each_parent_object, Roby::TaskStructure::Dependency).
                        map do |parent_task|
                            options = parent_task[task,
                                Roby::TaskStructure::Dependency]
                            [options[:roles].to_a.first, parent_task]
                        end

                    candidates = task.
                        enum_parent_objects(merge_graph).
                        find_all { |t| t.execution_agent }.
                        map { |t| t.orogen_spec.name }

                    @tasks[task] = [parents, candidates]
                end
            end

            def pretty_print(pp)
                pp.text "cannot deploy the following tasks"
                tasks.each do |task, (parents, possible_deployments)|
                    pp.breakable
                    pp.text task.to_s
                    pp.nest(2) do
                        pp.breakable
                        pp.seplist(parents) do |parent_task|
                            role, parent_task = parent_task
                            pp.text "child #{role} of #{parent_task}"
                        end
                    end
                end

                tasks.each do |task, (parents, possible_deployments)|
                    pp.breakable
                    if possible_deployments.empty?
                        pp.text "#{task}: no deployments available"
                    else
                        pp.text "#{task}: multiple possible deployments, #{possible_deployments.join(", ")}"
                    end
                end
            end
        end

        class InstanciationError < SpecError
            # The instanciation chain, i.e. an array of composition models that
            # were being instanciated
            attr_reader :instanciation_chain

            def initialize
                @instanciation_chain = []
            end

            def pretty_print(pp)
                if !instanciation_chain.empty?
                    pp.text "while instanciating"
                    pp.nest(2) do
                        pp.breakable
                        pp.seplist(instanciation_chain.reverse) do |m|
                            m.pretty_print(pp)
                        end
                    end
                end
            end
        end

        # Exception raised when the user provided a composition child selection
        # that is not compatible with the child definition
        class InvalidSelection < InstanciationError
            # The composition model
            attr_reader :composition_model
            # The child name for which the selection is invalid
            attr_reader :child_name
            # The model selected by the user
            attr_reader :selected_model
            # The model required by the composition for +child_name+
            attr_reader :required_models

            def initialize(composition_model, child_name, selected_model, required_models)
                super()
                @composition_model, @child_name, @selected_model, @required_models =
                    composition_model, child_name, selected_model, required_models
            end

            def pretty_print(pp)
                pp.text "cannot use #{selected_model.short_name} for the child #{child_name} of #{composition_model.short_name}"
                pp.breakable
                pp.text "it does not provide the required models"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(required_models) do |m|
                        pp.text m.short_name
                    end
                end
            end
        end

        # Exception raised during instanciation if a name is found that cannot
        # be resolved
        class NameResolutionError < InstanciationError
            # The missing name
            attr_reader :missing_name
            # The set of known names
            attr_reader :known_names

            def initialize(missing_name, known_names)
                super()
                @missing_name = missing_name
                @known_names = known_names.to_a
            end

            def pretty_print(pp)
                pp.text "#{missing_name} is neither a device nor an instance definition. Known names are: #{known_names.sort.join(', ')}"
                if !instanciation_chain.empty?
                    pp.breakable
                    super
                end
            end
        end

        class AmbiguousAutoConnection < Ambiguous
            # The composition model in which the automatic connection was to be
            # computed
            attr_reader :composition_model
            # The type name of the ports are involved
            attr_reader :type_name
            # The set of output candidates
            attr_reader :outputs
            # The set of input candidates
            attr_reader :inputs

            def initialize(composition_model, type_name, inputs, outputs)
                @composition_model, @type_name, @inputs, @outputs =
                    composition_model, type_name, inputs, outputs
            end

            def pretty_print_ports(pp, port_set)
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(port_set) do |port_description|
                        child_name, port_name = port_description
                        child_spec   = composition_model.find_child(child_name)
                        child_models = child_spec.models.map(&:short_name)
                        pp.text "#{child_name}.#{port_name} where"
                        pp.nest(2) do
                            pp.breakable
                            pp.text "#{child_name}'s model is #{child_models.join(", ")}"
                        end
                    end
                end
            end

            def pretty_print(pp)
                pp.text "there is an ambiguity while automatically computing connections in #{composition_model.short_name}"
                pp.breakable
                pp.text "the considered port type is #{type_name}"
                pp.breakable
                pp.text "involved outputs:"
                pretty_print_ports(pp, outputs)
                pp.breakable
                pp.text "involved inputs:"
                pretty_print_ports(pp, inputs)
            end
        end
    
        # Exception raised by CompositionModel#instanciate when multiple
        # specializations can be applied
        class AmbiguousSpecialization < Ambiguous
            # The composition model that was being instanciated
            attr_reader :composition_model
            # The user selection (see Composition.instanciate for details)
            attr_reader :selection
            # The set of possible specializations given the model and the
            # selection. This is a list of [merged, set] tuples where +set+ is
            # a set of specializations and +merged+ the complete specialization
            # model
            attr_reader :candidates

            def initialize(composition_model, selection, candidates)
                @composition_model, @selection, @candidates =
                    composition_model, selection, candidates
            end

            def pretty_print(pp)
                pp.text "there is an ambiguity in the instanciation of #{composition_model.short_name}"
                pp.breakable
                if selection.empty?
                    pp.text "with no selection applied"
                else
                    pp.text "with the following selection:"
                    pp.nest(2) do
                        pp.breakable
                        pp.seplist(selection) do |keyvalue|
                            key, value = *keyvalue
                            if key.respond_to?(:short_name)
                                key = key.short_name
                            end
                            value = value.requirements.models
                            value = value.map do |v|
                                if v.respond_to?(:short_name) then v.short_name
                                else v.to_s
                                end
                            end

                            pp.text "#{key} => #{value.join(",")}"
                        end
                    end
                end
                pp.breakable
                pp.text "the following specializations apply:"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(candidates) do |spec|
                        pp.text spec[0].short_name
                    end
                end
            end
        end
    end
end


