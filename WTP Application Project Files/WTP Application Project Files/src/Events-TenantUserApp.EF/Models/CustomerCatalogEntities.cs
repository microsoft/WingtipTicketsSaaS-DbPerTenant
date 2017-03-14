using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Events_TenantUserApp.EF.Models
{
    /// <summary>
    /// Partial class to override the connection string
    /// </summary>
    /// <seealso cref="System.Data.Entity.DbContext" />
    public partial class CustomerCatalogEntities
    {
        public CustomerCatalogEntities(string connectionString)
            : base(connectionString)
        {

        }
    }
}
