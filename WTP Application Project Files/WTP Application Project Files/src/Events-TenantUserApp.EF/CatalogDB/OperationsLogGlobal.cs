using System;

namespace Events_TenantUserApp.EF.CatalogDB
{
    public partial class OperationsLogGlobal
    {
        public Guid OperationId { get; set; }
        public int OperationCode { get; set; }
        public string Data { get; set; }
        public int UndoStartState { get; set; }
        public Guid? ShardVersionRemoves { get; set; }
        public Guid? ShardVersionAdds { get; set; }
    }
}
