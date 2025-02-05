# DistributedAccessControl
A distributed synchronization system implementing the Readers-Writers problem using the Ricart-Agrawala algorithm in Elixir. Designed to ensure efficient and scalable mutual exclusion without a central coordinator.

## Overview
This project implements a distributed synchronization system for managing concurrent access to a shared resource, specifically addressing the **Readers-Writers** problem. The solution leverages the **Ricart-Agrawala** algorithm, extended to support multiple operation types, ensuring a fair and efficient execution without a central coordinator.

## Features
- Implements the **generalized Ricart-Agrawala algorithm** for distributed mutual exclusion.
- Supports concurrent readers while ensuring exclusive access for writers.
- Uses **Lamport timestamps** to maintain proper request ordering.
- Built with **Elixir**, leveraging its concurrency model for efficient process communication.

## How It Works
- Readers can access the resource simultaneously.
- Writers require exclusive access, preventing other readers or writers from interacting with the resource.
- A logical clock system ensures requests are handled in the correct order, avoiding conflicts.

## Requirements
- [Elixir](https://elixir-lang.org/) installed.
- Basic understanding of distributed systems and process synchronization.
