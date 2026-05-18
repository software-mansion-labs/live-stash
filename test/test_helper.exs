# OTP 25+ will disconnect peer nodes when it detects a topology
# that looks like a healing partition - unwanted during tests
Application.put_env(:kernel, :prevent_overlapping_partitions, false)

ExUnit.start()
:logger.set_primary_config(:level, :warning)
