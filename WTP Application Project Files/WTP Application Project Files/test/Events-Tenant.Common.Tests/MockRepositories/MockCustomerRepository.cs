using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Tests.MockRepositories
{
    public class MockCustomerRepository : ICustomerRepository
    {
        private CustomerModel CustomerModel { get; set; }

        public int Add(CustomerModel customeModel, string connectionString, int tenantId)
        {
            CustomerModel = customeModel;
            return 123;
        }

        public CustomerModel GetCustomer(string email, string connectionString, int tenantId)
        {
            return CustomerModel;
        }
    }
}
