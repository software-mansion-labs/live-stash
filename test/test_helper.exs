# OTP 25+ will disconnect peer nodes when it detects a topology
# that looks like a healing partition - unwanted during tests
Application.put_env(:kernel, :prevent_overlapping_partitions, false)

# Memento depends on :mnesia, which auto-starts at app boot as :nonode@nohost.
# Tests that use :peer later distribute this node, leaving Mnesia's schema
# bound to a stale node name. Distribute first, then restart Mnesia so its
# schema matches the current node name.
LiveStash.TestSupport.ClusterHelpers.ensure_distribution_started!()
:mnesia.stop()
:mnesia.start()

ExUnit.start()
:logger.set_primary_config(:level, :warning)
