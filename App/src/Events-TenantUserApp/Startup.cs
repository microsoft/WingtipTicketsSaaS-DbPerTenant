using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using Events_Tenant.Common.Interfaces;
using Events_Tenant.Common.Repositories;
using Events_Tenant.Common.Utilities;
using Events_TenantUserApp.EF.CatalogDB;
using Events_TenantUserApp.ViewModels;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Localization;
using Microsoft.AspNetCore.Mvc.Razor;
using Microsoft.Azure.SqlDatabase.ElasticScale.ShardManagement;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using DnsClient;

namespace Events_TenantUserApp
{
    /// <summary>
    /// The project Startup class
    /// </summary>
    public class Startup
    {
        #region Private fields
        private IUtilities _utilities;
        private ICatalogRepository _catalogRepository;
        private ITenantRepository _tenantRepository;
        private ILookupClient _client;
        #endregion

        #region Public Properties
        public static DatabaseConfig DatabaseConfig { get; set; }
        public static CatalogConfig CatalogConfig { get; set; }
        public static TenantServerConfig TenantServerConfig { get; set; }
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
        }

        #endregion

        #region Public methods

        /// <summary>
        /// This method gets called by the runtime. Use this method to add services to the container.
        /// </summary>
        /// <param name="services">The services.</param>
        public void ConfigureServices(IServiceCollection services)
        {
            //Localisation settings
            services.AddLocalization(options => options.ResourcesPath = "Resources");

            // Add framework services.
            services.AddMvc()
                .AddViewLocalization(LanguageViewLocationExpanderFormat.Suffix)
                .AddDataAnnotationsLocalization();

            // Adds a default in-memory implementation of IDistributedCache.
            services.AddDistributedMemoryCache();
            services.AddSession();

            //register catalog DB
            services.AddDbContext<CatalogDbContext>(options => options.UseSqlServer(GetCatalogConnectionString(CatalogConfig, DatabaseConfig)));

            //Add Application services
            services.AddTransient<ICatalogRepository, CatalogRepository>();
            services.AddTransient<ITenantRepository, TenantRepository>();
            services.AddSingleton<ITenantRepository>(p => new TenantRepository(GetBasicSqlConnectionString()));
            services.AddSingleton<IConfiguration>(Configuration);
            services.AddSingleton<ILookupClient>(p => new LookupClient());

            //create instance of utilities class
            services.AddTransient<IUtilities, Utilities>();
            var provider = services.BuildServiceProvider();
            _utilities = provider.GetService<IUtilities>();
            _catalogRepository = provider.GetService<ICatalogRepository>();
            _tenantRepository = provider.GetService<ITenantRepository>();
            _client = provider.GetService<ILookupClient>();
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

            #region Localisation settings

            //get the list of supported cultures from the appsettings.json
            var allSupportedCultures = Configuration.GetSection("SupportedCultures").Get<SupportedCultures>();
            var defaultCulture = Configuration["DefaultRequestCulture"];

            if (allSupportedCultures != null && defaultCulture != null)
            {
                List<CultureInfo> supportedCultures = allSupportedCultures.SupportedCulture.Select(t => new CultureInfo(t)).ToList();

                app.UseRequestLocalization(new RequestLocalizationOptions
                {
                    DefaultRequestCulture = new RequestCulture(defaultCulture),
                    //get the default culture from appsettings.json
                    SupportedCultures = supportedCultures, // UI strings that we have localized.
                    SupportedUICultures = supportedCultures,
                    RequestCultureProviders = new List<IRequestCultureProvider>()
                });
            }
            else
            {
                app.UseRequestLocalization(new RequestLocalizationOptions
                {
                    DefaultRequestCulture = new RequestCulture("en-US"),
                    RequestCultureProviders = new List<IRequestCultureProvider>()
                });
            }

            #endregion

            app.UseSession();

            //adding the cookie middleware
            app.UseCookieAuthentication(new CookieAuthenticationOptions()
            {
                AuthenticationScheme = "MyCookieMiddlewareInstance",
                AutomaticAuthenticate = true,
                AutomaticChallenge = true
            });

            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller=Home}/{action=Index}/{id?}");

                routes.MapRoute(
                    name: "default_route",
                    template: "{tenant}/{controller=Home}/{action=Index}/{id?}");

                routes.MapRoute(
                    name: "TenantAccount",
                    template: "{tenant}/{controller=Account}/{action=Index}/{id?}");

                routes.MapRoute(
                    name: "FindSeats",
                    template: "{tenant}/{controller=FindSeats}/{action=Index}/{id?}");

            });

            //shard management
            InitialiseShardMapManager();
            _utilities.RegisterTenantShard(TenantServerConfig, DatabaseConfig, CatalogConfig, TenantServerConfig.ResetEventDates);
        }

        #endregion

        #region Private methods

        /// <summary>
        ///  Gets the catalog connection string using the app settings
        /// </summary>
        /// <param name="catalogConfig">The catalog configuration.</param>
        /// <param name="databaseConfig">The database configuration.</param>
        /// <returns></returns>
        private string GetCatalogConnectionString(CatalogConfig catalogConfig, DatabaseConfig databaseConfig)
        {
            return
                $"Server=tcp:{catalogConfig.CatalogServer},1433;Database={catalogConfig.CatalogDatabase};User ID={databaseConfig.DatabaseUser};Password={databaseConfig.DatabasePassword};Trusted_Connection=False;Encrypt=True;";
        }

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
                SqlProtocol = SqlProtocol.Tcp,
                ConnectionTimeOut = Convert.ToInt32(Configuration["ConnectionTimeOut"]),
                LearnHowFooterUrl = Configuration["LearnHowFooterUrl"]
            };

            CatalogConfig = new CatalogConfig
            {
                CatalogAlias = Configuration["CatalogAlias"],
                ServicePlan = Configuration["ServicePlan"],
                CatalogDatabase = Configuration["CatalogDatabase"],
                CatalogServer = Configuration["CatalogServer"] + ".database.windows.net"
            };

            TenantServerConfig = new TenantServerConfig
            {
                TenantServer = Configuration["TenantServer"] + ".database.windows.net",
                ContosoConcertHallServerAlias = Configuration["ContosoConcertHallAlias"] + ".database.windows.net",
                FabrikamJazzClubServerAlias = Configuration["FabrikamJazzClubAlias"] + ".database.windows.net",
                DogwoodDojoServerAlias = Configuration["DogwoodDojoAlias"] + ".database.windows.net"
            };

            bool isResetEventDatesEnabled = false;
            if (bool.TryParse(Configuration["ResetEventDates"], out isResetEventDatesEnabled))
            {
                TenantServerConfig.ResetEventDates = isResetEventDatesEnabled;
            }
        }

        /// <summary>
        /// Initialises the shard map manager and shard map 
        /// <para>Also does all tasks related to sharding</para>
        /// </summary>
        private void InitialiseShardMapManager()
        {
            var basicConnectionString = GetBasicSqlConnectionString();
            SqlConnectionStringBuilder connectionString = new SqlConnectionStringBuilder(basicConnectionString)
            {
                DataSource = DatabaseConfig.SqlProtocol + ":" + CatalogConfig.CatalogServer + "," + DatabaseConfig.DatabaseServerPort,
                InitialCatalog = CatalogConfig.CatalogDatabase
            };

            var sharding = new Sharding(CatalogConfig.CatalogDatabase, connectionString.ConnectionString, _catalogRepository, _tenantRepository, _utilities);
        }

        /// <summary>
        /// Gets the basic SQL connection string.
        /// </summary>
        /// <returns></returns>
        private string GetBasicSqlConnectionString()
        {
            var connStrBldr = new SqlConnectionStringBuilder
            {
                UserID = DatabaseConfig.DatabaseUser,
                Password = DatabaseConfig.DatabasePassword,
                ApplicationName = "EntityFramework",
                ConnectTimeout = DatabaseConfig.ConnectionTimeOut,
                LoadBalanceTimeout = 15
            };

            return connStrBldr.ConnectionString;
        }
        #endregion

    }
}
