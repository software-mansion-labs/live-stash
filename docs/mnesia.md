# Mnesia

## Description

The Mnesia adapter stores LiveView state on the server using Mnesia through
the Amnesia wrapper. It uses Mnesia replication to make state recovery easier, and redeploys possible. State is stashed into native Mnesia table copies, recovered from the local copy on reconnect, and cleared
when you reset the stash.

## Replication

The adapter always configures native Mnesia table copies on connected nodes and
relies on Mnesia replication for writes/deletes.

Recovery is local because every serving node is expected to have the table
copy already.

## When to use

Choose the Mnesia adapter when:

- **BEAM native solution:** You want a fully server-side solution that leverages the BEAM's distributed capabilities without relying on external services like Redis.
- **State durability (Rolling Redeploys):** You need stashed state to survive rolling server restarts and redeployments. Thanks to Mnesia's replication, the state persists as long as at least one node in the cluster remains active. _(Note: A simultaneous shutdown of the entire cluster will clear the state)._
- **Clustering:** You have a clustered application where client can connect to different nodes.
