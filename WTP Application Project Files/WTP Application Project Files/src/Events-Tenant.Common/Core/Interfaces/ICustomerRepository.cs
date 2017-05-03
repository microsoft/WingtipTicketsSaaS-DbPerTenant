using Events_Tenant.Common.Models;

namespace Events_Tenant.Common.Core.Interfaces
{
  public  interface ICustomerRepository
  {
      int Add(CustomerModel customeModel, string connectionString, int tenantId);

      CustomerModel GetCustomer(string email, string connectionString, int tenantId);
  }
}
