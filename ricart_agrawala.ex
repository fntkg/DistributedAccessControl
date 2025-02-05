defmodule RicartAgrawala do
	#===================================================================
	# Communication and Synchronization Functions for Critical Section Entry
	#===================================================================

	# Sends a REQUEST message to the last process in the list.
	# Base case (remaining_count = 1): when there is only one process in the list.
	#
	# Parameters:
	# - logical_clock: the current logical clock value (for ordering requests)
	# - process_id: identifier of the current process (a strictly increasing integer)
	# - operation_type: type of operation (e.g., :read or :write)
	# - target_processes: list of process PIDs to which we must send the request
	# - remaining_count: the number of processes left in the list (here remaining_count <= 1 for the base case)
	# - target_field: the variable (or field) that the process intends to modify
	def loop_send(logical_clock, process_id, operation_type, target_processes, remaining_count, target_field) when remaining_count <= 1 do
	  [first_process | _] = target_processes
	  IO.puts("Value of process_id: #{inspect(process_id)}")
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Loop send, base case: #{inspect(first_process)}")
	  send(first_process, {:REQUEST, logical_clock, self(), operation_type, target_field, process_id})
	end

	# Recursively sends the REQUEST message to each process in the list.
	#
	# Parameters are the same as above, but now remaining_count > 1.
	def loop_send(logical_clock, process_id, operation_type, target_processes, remaining_count, target_field) do
	  [first_process | rest_processes] = target_processes
	  IO.puts("Value of process_id: #{inspect(process_id)}")
	  send(first_process, {:REQUEST, logical_clock, self(), operation_type, target_field, process_id})
	  loop_send(logical_clock, process_id, operation_type, rest_processes, remaining_count - 1, target_field)
	end

	# Waits to receive a single PERMISSION message.
	# Base case (remaining_permissions = 1): waits for one permission.
	def loop_receive(remaining_permissions) when remaining_permissions <= 1 do
	  receive do
		{:PERMISSION} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Received PERMISSION from process #{inspect(remaining_permissions)} [BASE CASE]!")
		  true
	  end
	end

	# Waits to receive remaining_permissions PERMISSION messages recursively.
	def loop_receive(remaining_permissions) do
	  receive do
		{:PERMISSION} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Received PERMISSION from process #{inspect(remaining_permissions)}!")
		  true
	  end
	  loop_receive(remaining_permissions - 1)
	end

	# Exclusion matrix to determine if two operations can be executed concurrently.
	#
	# Parameters:
	# - op_type_a, op_type_b: operation types (e.g., :escribir (write) or :leer (read))
	# - field_name: the field on which the operation is performed
	# - target_field: the field that is being modified
	#
	# Returns true if the operations conflict (i.e. they access the same field and at least one is a write).
	def exclude(op_type_a, op_type_b, field_name, target_field) do
	  IO.puts("exclude parameters TARGET_FIELD: #{inspect(target_field)} FIELD_NAME: #{inspect(field_name)} A: #{inspect(op_type_a)} B: #{inspect(op_type_b)}")
	  if (field_name == target_field) and (op_type_a == :escribir || op_type_b == :escribir) do
		true
	  else
		false
	  end
	end

	# Sends a PERMISSION message to the only process in the list (base case).
	def send_permission(target_processes, remaining_count) when remaining_count <= 1 do
	  [first_process | _] = target_processes
	  send(first_process, {:PERMISSION})
	end

	# Recursively sends a PERMISSION message to every process in the list.
	def send_permission(target_processes, remaining_count) do
	  [first_process | rest_processes] = target_processes
	  send(first_process, {:PERMISSION})
	  send_permission(rest_processes, remaining_count - 1)
	end

	#===================================================================
	# Protocol for Entering and Exiting the Critical Section
	#===================================================================

	# Called by a process to begin its operation (i.e. to enter the critical section).
	#
	# Parameters:
	# - process_id: process identifier (strictly increasing integer)
	# - operation_type: type of operation the process wants to perform (e.g., :escribir or :leer)
	# - target_field: the variable (or field) the process intends to modify (e.g., :uno, :dos, or :tres)
	def begin_op(process_id, operation_type, target_field) do
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: !!PRE-PROTOCOL START!!")
	  # Spawn a new process that will handle the request protocol.
	  request_process = spawn(RicartAgrawala, :request, [operation_type, target_field, process_id])

	  # Tell the process that maintains the list of request processes to add this new request process.
	  send({:list_process, :"list@127.0.0.1"}, {:add, request_process})
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Sending message to change state")
	  send(request_process, {:TRYING, self()})
	  IO.puts("Test value of request process PID: #{inspect(request_process)}")

	  # Wait to receive the logical clock (ldr)
	  receive do
		{:ldr, logical_clock} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Received LDR: #{inspect(logical_clock)}")
		  # Request process list (handled by another process)
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: --- !DEBUG DELAY! ---")
		  Process.sleep(10000)
		  send({:list_process, :"list@127.0.0.1"}, {:get, self(), process_id})
		  receive do
			process_list ->
			  if List.first(process_list) != nil do
				# Send REQUEST to every process in the list and wait for all PERMISSION messages
				loop_send(logical_clock, process_id, operation_type, process_list, length(process_list), target_field)
				IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Waiting for response from ALL processes in the list!")
				loop_receive(length(process_list))
			  end
		  end

		  # After receiving permission from all processes, inform the request process to change its state to IN.
		  send(request_process, {:IN})

		  # -------------------------
		  # Enter the Critical Section:
		  IO.puts(" #{inspect(self())} #{inspect(Time.utc_now)}: --- CRITICAL SECTION ---")
		  IO.puts(" #{inspect(self())} #{inspect(Time.utc_now)}: PROCESS ENTERED CRITICAL SECTION WITH CLOCK: #{inspect(logical_clock)}")
		  Process.sleep(10000)
		  IO.puts(" #{inspect(self())} #{inspect(Time.utc_now)}: --- /CRITICAL SECTION ---")
		  # End the operation (exit the critical section)
		  end_op(request_process)
	  end
	end

	# Called when the process exits the critical section.
	#
	# Parameters:
	# - request_process: the PID of the request process handling the protocol.
	def end_op(request_process) do
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: !!POST-PROTOCOL START!!")
	  # Inform the request process to change state to OUT.
	  send(request_process, {:OUT})
	  # Tell the request process to send out delayed PERMISSION messages to any waiting processes.
	  send(request_process, {:PERMISSION})
	end

	#===================================================================
	# Request Process for Handling State and Incoming Messages
	#===================================================================

	# This function runs concurrently with the main process.
	# It maintains the state of the process in the protocol.
	#
	# Parameters:
	# - local_clock: the local logical clock value
	# - state: current state (e.g., :out, :trying, :in)
	# - operation_type: type of operation the process is trying to perform (e.g., :escribir or :leer)
	# - last_received_clock: the last received clock value (used to compare priorities)
	# - delayed_permissions: list of PIDs that are waiting for delayed permission
	# - field_name: the field on which the operation is performed
	# - process_id: process identifier
	def request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id) do
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: REQUEST STATE: clock=#{inspect(local_clock)} state=#{inspect(state)} operation_type=#{inspect(operation_type)} last_received_clock=#{inspect(last_received_clock)} delayed_permissions=#{inspect(delayed_permissions)} field_name=#{inspect(field_name)}")
	  receive do
		# Change state to TRYING.
		{:TRYING, caller_pid} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: ENTERING TRYING STATE!")
		  state = :trying
		  # Ask the clock server for the current clock.
		  send({:clock, :"clock@127.0.0.1"}, {:get_clock, self()})
		  receive do
			{:clock_received, current_clock} ->
			  # Update logical clock (here, simply incrementing local_clock by 1).
			  updated_clock = local_clock + 1
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: REQUEST received clock: #{inspect(updated_clock)}")
			  # Send the clock (logical clock) to the process that initiated the operation.
			  send(caller_pid, {:ldr, updated_clock})
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: REQUEST sent clock to process")
			  # Continue running in the loop.
			  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
		  end

		# Handle an incoming REQUEST message from another process.
		#
		# Message parameters:
		# - request_clock: clock value from the requesting process.
		# - external_pid: PID of the external process that is requesting access.
		# - external_op_type: operation type requested by the external process.
		# - target_field: variable/field that the external process wants to modify.
		# - external_process_id: identifier of the external process.
		{:REQUEST, request_clock, external_pid, external_op_type, target_field, external_process_id} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: local_clock: #{inspect(local_clock)} request_clock: #{inspect(request_clock)} last_received_clock: #{inspect(last_received_clock)}")
		  # Update own clock to the maximum between local_clock and the received clock.
		  local_clock = max(local_clock, request_clock)

		  # Determine whether to delay sending permission.
		  if (last_received_clock == request_clock) do
			IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: All good up to here")
			delay_permission = (state != :out) and (process_id < external_process_id) and exclude(external_op_type, operation_type, field_name, target_field)
			if delay_permission do
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: DELAYING! external_process_id: #{inspect(external_process_id)} process_id: #{inspect(process_id)}")
			  delayed_permissions = delayed_permissions ++ [external_pid]
			  IO.puts("Delayed permissions list: #{inspect(delayed_permissions)}")
			  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
			else
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: SENDING PERMISSION! external_process_id: #{inspect(external_process_id)} process_id: #{inspect(process_id)}")
			  send(external_pid, {:PERMISSION})
			  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
			end
		  else
			delay_permission = (state != :out) and (last_received_clock < request_clock) and exclude(external_op_type, operation_type, field_name, target_field)
			if delay_permission do
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: DELAYING! external_process_id: #{inspect(external_process_id)} process_id: #{inspect(process_id)}")
			  # Add external_pid to the list of delayed permissions.
			  delayed_permissions = delayed_permissions ++ [external_pid]
			  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
			else
			  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: SENDING PERMISSION! external_process_id: #{inspect(external_process_id)} process_id: #{inspect(process_id)}")
			  # Send permission immediately.
			  send(external_pid, {:PERMISSION})
			  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
			end
		  end

		  IO.puts("Delayed permissions list: #{inspect(delayed_permissions)}")

		# Change state to IN when entering the critical section.
		{:IN} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Changing state to :IN")
		  state = :in
		  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)

		# Change state to OUT when exiting the critical section.
		{:OUT} ->
		  IO.puts("Changing state to :OUT")
		  state = :out
		  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)

		# Process a request to send delayed permissions.
		{:PERMISSION} ->
		  IO.puts("Delayed permissions list when processing PERMISSION: #{inspect(delayed_permissions)}")
		  if length(delayed_permissions) != 0 do
			IO.puts("Sending delayed permissions. List: #{inspect(delayed_permissions)}")
			send_permission(delayed_permissions, length(delayed_permissions))
		  else
			IO.puts("Delayed permissions list empty, skipping...")
		  end
		  request(local_clock, state, operation_type, last_received_clock, delayed_permissions, field_name, process_id)
	  end
	end

	# Helper function to initialize the request process.
	# This function only requires the operation type, the field being accessed, and the process ID.
	def request(operation_type, field_name, process_id) do
	  # Initialize with local_clock = 0, state = :out, last_received_clock = 0, and an empty list for delayed permissions.
	  request(0, :out, operation_type, 0, [], field_name, process_id)
	end

	#===================================================================
	# Clock Server Functions
	#===================================================================

	# Starts the clock server process.
	def init_clock() do
	  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: Clock server started")
	  clock(0)
	end

	# Clock server loop: waits for a request and sends the current clock value.
	#
	# Parameters:
	# - clock_value: current clock value.
	def clock(clock_value) do
	  receive do
		{:get_clock, pid} ->
		  IO.puts("#{inspect(self())} #{inspect(Time.utc_now)}: CLOCK SV: Delivering clock value: #{inspect(clock_value)}")
		  send(pid, {:clock_received, clock_value})
	  end
	  clock(clock_value + 1)
	end

	#===================================================================
	# Process List Server Functions
	#===================================================================

	# Initializes the process list server.
	# This process keeps track of all request processes.
	def init_list() do
	  request_process_list(1, [])
	  IO.puts("Process list server started")
	end

	# Loop that manages the list of request processes.
	#
	# Parameters:
	# - index_counter: a counter (used as an index or identifier)
	# - process_list: current list of process PIDs
	def request_process_list(index_counter, process_list) do
	  IO.puts("Current list state: #{inspect(process_list)}")
	  receive do
		{:add, request_pid} ->
		  IO.puts("Adding process!")
		  process_list = process_list ++ [request_pid]
		  IO.puts("Updated list: #{inspect(process_list)}")
		  request_process_list(index_counter + 1, process_list)
		{:get, caller_pid, list_index} ->
		  # Remove the process at position list_index (if needed) and send the list.
		  filtered_list = List.delete_at(process_list, list_index)
		  IO.puts("GET request. Deleting index #{inspect(list_index)}. List sent: #{inspect(filtered_list)}")
		  send(caller_pid, filtered_list)
		  request_process_list(list_index, process_list)
	  end
	end
  end

  #===================================================================
  # Repository Module
  #===================================================================

  defmodule Repository do
	@moduledoc """
	A simple repository server that maintains three pieces of data.
	The repository responds to update and read requests for three fields:
	- summary
	- main
	- delivery
	"""

	# Initializes the repository with empty values.
	def init do
	  repo_server({"", "", ""})
	end

	# Repository server loop.
	# The state is maintained as a tuple {summary, main, delivery}.
	#
	# The server receives messages to update or read each field.
	defp repo_server({summary, main, delivery}) do
	  {new_summary, new_main, new_delivery} =
		receive do
		  # Update the "summary" field.
		  {:update_summary, client_pid, description} ->
			send(client_pid, {:reply, :ok})
			{description, main, delivery}
		  # Update the "main" field.
		  {:update_main, client_pid, description} ->
			send(client_pid, {:reply, :ok})
			{summary, description, delivery}
		  # Update the "delivery" field.
		  {:update_delivery, client_pid, description} ->
			send(client_pid, {:reply, :ok})
			{summary, main, description}
		  # Read the "summary" field.
		  {:read_summary, client_pid} ->
			send(client_pid, {:reply, summary})
			{summary, main, delivery}
		  # Read the "main" field.
		  {:read_main, client_pid} ->
			send(client_pid, {:reply, main})
			{summary, main, delivery}
		  # Read the "delivery" field.
		  {:read_delivery, client_pid} ->
			send(client_pid, {:reply, delivery})
			{summary, main, delivery}
		end
	  # Continue serving requests with the updated state.
	  repo_server({new_summary, new_main, new_delivery})
	end
  end
