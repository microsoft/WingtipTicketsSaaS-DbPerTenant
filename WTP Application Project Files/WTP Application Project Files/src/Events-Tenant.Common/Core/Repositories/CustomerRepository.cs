using System.Linq;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;
using Events_TenantUserApp.EF.TenantsDB;

namespace Events_Tenant.Common.Core.Repositories
{
    public class CustomerRepository: BaseRepository, ICustomerRepository
    {
        public int Add(CustomerModel customeModel, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var customer = new Customers
                {
                    CountryCode = customeModel.CountryCode,
                    Email = customeModel.Email,
                    FirstName = customeModel.FirstName,
                    LastName = customeModel.LastName,
                    PostalCode = customeModel.PostalCode
                };

                context.Customers.Add(customer);
                context.SaveChanges();

                return customer.CustomerId;
            }
        }

        public CustomerModel GetCustomer(string email, string connectionString, int tenantId)
        {
            using (var context = CreateContext(connectionString, tenantId))
            {
                var customers = context.Customers.Where(i => i.Email == email);

                if (customers.Any())
                {
                    var customer = customers.FirstOrDefault();
                    return new CustomerModel
                    {
                        FirstName = customer.FirstName,
                        Email = customer.Email,
                        PostalCode = customer.PostalCode,
                        LastName = customer.LastName,
                        CountryCode = customer.CountryCode,
                        CustomerId = customer.CustomerId
                    };
                }
            }
            return null;
        }
    }
}
