# Restore 'contosoconcerthall' database to 30 minutes ago in parallel with original instance
.\RestoreTenantdata.ps1 -ResourceGroupName "Wingtip-ayo1" -User "ayo1" -TenantName "contosoconcerthall" -RestorePoint (Get-Date).AddMinutes(-30) -InParallel

# Restore 'fabrikamjazzclub' database to 10 minutes ago
.\RestoreTenantdata.ps1 -ResourceGroupName "Wingtip-ayo1" -User "ayo1" -TenantName "fabrikamjazzclub" -RestorePoint (Get-Date).AddMinutes(-10) -InPlace

# Add or delete event in 'fabrikamjazzclub' webpage. Try to recover the database from a point in time 2 hours ago. 
# This should fetch previous tenant database instance and recover from that
.\RestoreTenantdata.ps1 -ResourceGroupName "Wingtip-ayo1" -User "ayo1" -TenantName "fabrikamjazzclub" -RestorePoint (Get-Date).AddMinutes(-120) -InPlace

