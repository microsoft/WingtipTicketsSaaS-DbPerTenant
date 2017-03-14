using System;
using Events_Tenant.Common.Core.Interfaces;
using Events_Tenant.Common.Core.Repositories;
using Events_Tenant.Common.Helpers;
using Events_Tenant.Common.Utilities;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Razor;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Events_TenantUserApp
{
    /// <summary>
    /// The project Startup class
    /// </summary>
    public class Startup
    {
        #region Private variables

        private Sharding _sharding;

        #endregion

        #region Public Properties
        public static DatabaseConfig DatabaseConfig { get; set; }
        public static CustomerCatalogConfig CustomerCatalogConfig { get; set; }
        public static TenantServerConfig TenantServerConfig { get; set; }
        public static TenantConfig TenantConfig { get; set; }
        public IConfigurationRoot Configuration { get; }

        #endregion

        #region Constructor

        /// <summary>
        /// Initializes a new instance of the <see cref="Startup"/> class.
        /// </summary>
        /// <param name="env">The env.</param>
        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", optional: true)
                .AddEnvironmentVariables();
            Configuration = builder.Build();

            //read config settigs from appsettings.json
            ReadAppConfig();

            InitialiseShardMapManager();

            if (TenantServerConfig.ResetEventDates)
            {
                Helper.ResetTenantEventDates(TenantServerConfig, DatabaseConfig, CustomerCatalogConfig);
            }


            //RequestInitialization RequestInitialization = new RequestInitialization();
            //RequestInitialization.InitializeTenantConfig();
            //   InitializeTenantConfig();
        }

        #endregion

        #region Public methods

        /// <summary>
        /// This method gets called by the runtime. Use this method to add services to the container.
        /// </summary>
        /// <param name="services">The services.</param>
        public void ConfigureServices(IServiceCollection services)
        {
            // Add framework services.
            services.AddMvc()
            .AddViewLocalization(LanguageViewLocationExpanderFormat.Suffix)
            .AddDataAnnotationsLocalization();


            services.AddTransient<IHttpContextAccessor, HttpContextAccessor>();
            services.AddLocalization(options => options.ResourcesPath = "Resources");

            //Add Application services
            services.AddTransient<IEventsRepository, EventsRepository>();
            services.AddTransient<ITenantsRepository, TenantsRepository>();
            services.AddTransient<IVenuesRepository, VenuesRepository>();
            services.AddTransient<IVenueTypesRepository, VenueTypesRepository>();
        }

        /// <summary>
        /// This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        /// </summary>
        /// <param name="app">The application.</param>
        /// <param name="env">The env.</param>
        /// <param name="loggerFactory">The logger factory.</param>
        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"));
            loggerFactory.AddDebug();

            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                app.UseBrowserLink();
            }
            else
            {
                app.UseExceptionHandler("/Home/Error");
            }

            app.UseStaticFiles();

            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller=Home}/{action=Index}/{id?}");
            });
        }

        #endregion

        #region Private methods

        /// <summary>
        /// Reads the application settings from appsettings.json
        /// </summary>
        private void ReadAppConfig()
        {
            DatabaseConfig = new DatabaseConfig
            {
                DatabasePassword = Configuration["DatabasePassword"],
                DatabaseUser = Configuration["DatabaseUser"],
                DatabaseServerPort = Convert.ToInt32(Configuration["DatabaseServerPort"]),
                SqlProtocol = Configuration["SqlProtocol"],
                ConnectionTimeOut = Convert.ToInt32(Configuration["ConnectionTimeOut"])
            };

            CustomerCatalogConfig = new CustomerCatalogConfig
            {
                ServicePlan = Configuration["ServicePlan"],
                CustomerCatalogDatabase = Configuration["CustomerCatalogDatabase"],
                CustomerCatalogServer = Configuration["CustomerCatalogServer"] + ".database.windows.net"
            };

            TenantServerConfig = new TenantServerConfig
            {
                TenantServer = Configuration["TenantServer"] + ".database.windows.net",
                ResetEventDates = Convert.ToBoolean(Configuration["ResetEventDates"])
            };
        }


        /// <summary>
        /// Initialises the customer catalog and resets the events dates for all tenants
        /// <para>Also does all tasks related to sharding</para>
        /// </summary>
        private void InitialiseShardMapManager()
        {
            var connectionString = Helper.GetSqlConnectionString(DatabaseConfig);

            _sharding = new Sharding(connectionString, CustomerCatalogConfig, DatabaseConfig);
        }


        //private void InitializeTenantConfig()
        //{
        //    //get venuename from url

        //    string venueName = HttpContextAccessor.HttpContext.Request.PathBase;

        //    if (!string.IsNullOrEmpty(venueName) && venueName.Length > 1)
        //    {
        //        // Retrieve the tenant configuration details from the tenant's database
        //        var venue = venueName.Substring(1, venueName.Length - 2);
        //        //PopulateTenantConfig(venue);


        //        //// tenant configuration is placed in the context so it is available throughout the request
        //        //HttpContext.Current.Items.Add("TenantInfo", _tenantConfig);
        //    }
        //}

        #endregion 

    }
}
