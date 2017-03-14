using System.Collections.Generic;
using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Models;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.Models;

namespace Events_Tenant.Common.Core.Repositories
{
    public class EventsRepository : IEventsRepository
    {
        public IEnumerable<EventModel> GetEventsForTenant(byte[] tenantId, DatabaseConfig databaseConfig, TenantServerConfig tenantServerConfig)
        {
            var connectionString = Helper.GetSqlConnectionString(databaseConfig);

            using (var context = new TenantEntities(Sharding.ShardMap, tenantId, connectionString, Helper.GetTenantConnectionString(databaseConfig, tenantServerConfig)))
            {
                var events = context.Events.AsEnumerable();

                return events.Select(eventmodel => new EventModel
                {
                    Date = eventmodel.Date,
                    EventId = eventmodel.EventId,
                    EventName = eventmodel.EventName,
                    SubTitle = eventmodel.Subtitle
                }).ToList();
            }
        }
    }
}
