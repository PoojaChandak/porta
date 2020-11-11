# frozen_string_literal: true

require 'test_helper'

class FetchProxyConfigsServiceTest < ActiveSupport::TestCase
  def setup
    @provider = FactoryBot.create(:simple_provider)
    @service = FactoryBot.create(:simple_service, :with_default_backend_api, account: provider)
    @proxy = service.proxy
  end

  attr_reader :provider, :service, :proxy

  test 'search by environment' do
    ProxyConfig::ENVIRONMENTS.each { |env| FactoryBot.create_list(:proxy_config, 2, environment: env, proxy: proxy) }

    ProxyConfig::ENVIRONMENTS.each do |env|
      assert_same_elements proxy.proxy_configs.by_environment(env).select(:id).map(&:id), fetch_proxy_configs(environment: env).select(:id).map(&:id)
    end

    assert_raises(ProxyConfig::InvalidEnvironmentError) { fetch_proxy_configs(environment: 'invalid') }
  end

  test 'search by host' do
    hosts_list = [
      %w[3scale.localhost example.org],
      %w[3scale.net example.org 3sca.net],
      %w[3scale.localhost example.com]
    ]

    hosts_list.each do |hosts|
      FactoryBot.create_list(:proxy_config, 2,
                                proxy: proxy,
                                environment: ProxyConfig::ENVIRONMENTS.first,
                                content: { proxy: { hosts: hosts } }.to_json
      )
    end

    proxy_configs_by_example_org_host = proxy.proxy_configs.by_host('example.org').by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_by_example_org_host, fetch_proxy_configs(host: 'example.org').select(:id).map(&:id)

    proxy_configs_for_all_hosts = proxy.proxy_configs.by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_for_all_hosts, fetch_proxy_configs(host: nil).select(:id).map(&:id)
  end

  test 'search by version' do
    FactoryBot.create_list(:proxy_config, 3,
                           proxy: proxy,
                           environment: ProxyConfig::ENVIRONMENTS.first
    )

    proxy_configs_by_version_2 = proxy.proxy_configs.by_version(2).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_by_version_2, fetch_proxy_configs(version: 2).select(:id).map(&:id)
    assert_same_elements proxy_configs_by_version_2, fetch_proxy_configs(version: '2').select(:id).map(&:id)

    proxy_configs_by_latest_version = proxy.proxy_configs.by_version('latest').by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id, :version).map(&:id)
    assert_same_elements proxy_configs_by_latest_version, fetch_proxy_configs(version: 'latest').select(:id, :version).map(&:id)

    proxy_configs_for_all_versions = proxy.proxy_configs.by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_for_all_versions, fetch_proxy_configs(version: nil).select(:id).map(&:id)
  end

  test 'search by owner: service or provider' do
    another_service = FactoryBot.create(:simple_service, :with_default_backend_api, account: provider)
    service_of_another_provider = FactoryBot.create(:simple_service, :with_default_backend_api)
    [service, another_service, service_of_another_provider].each do |service|
      FactoryBot.create_list(:proxy_config, 2, proxy: service.proxy, environment: ProxyConfig::ENVIRONMENTS.first)
    end

    proxy_configs_of_provider = ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_of_provider, fetch_proxy_configs(owner: provider).select(:id).map(&:id)

    proxy_configs_of_service = service.proxy.proxy_configs.where(proxy_id: service.proxy.id).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id)
    assert_same_elements proxy_configs_of_service, fetch_proxy_configs(owner: service).select(:id).map(&:id)

    proxy_configs_of_another_owner_class = fetch_proxy_configs(owner: BackendApi.new).select(:id).map(&:id)
    assert_empty proxy_configs_of_another_owner_class
  end

  test 'search filters by permissions' do
    services = [service] | FactoryBot.create_list(:simple_service, 2, :with_default_backend_api, account: provider)
    services.each { |service| FactoryBot.create(:proxy_config, proxy: service.proxy, environment: ProxyConfig::ENVIRONMENTS.first) }

    admin = FactoryBot.create(:admin, account: provider)
    member_access_all_services = FactoryBot.create(:member, account: provider, admin_sections: ['partners'])
    member_access_all_services.update!(member_permission_service_ids: nil)
    member_access_some_services = FactoryBot.create(:member, account: provider, admin_sections: ['partners'])
    member_access_some_services.update!(member_permission_service_ids: services[0..1].map(&:id))
    member_with_sections_permissions_but_empty_services = FactoryBot.create(:member, account: provider, admin_sections: ['partners'])
    member_with_sections_permissions_but_empty_services.update!(member_permission_service_ids: '[]')


    rolling_update(:service_permissions, enabled: true)

    assert_same_elements(ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: admin).select(:id).map(&:id))

    assert_same_elements(ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: member_access_all_services).select(:id).map(&:id))

    assert_same_elements(ProxyConfig.for_services(services[0..1]).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: member_access_some_services).select(:id).map(&:id))

    assert_empty fetch_proxy_configs(owner: provider, watcher: member_with_sections_permissions_but_empty_services)



    rolling_update(:service_permissions, enabled: false)

    assert_same_elements(ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: admin).select(:id).map(&:id))

    assert_same_elements(ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: member_access_all_services).select(:id).map(&:id))

    assert_same_elements(ProxyConfig.for_services(provider.services).by_environment(ProxyConfig::ENVIRONMENTS.first).select(:id).map(&:id),
                         fetch_proxy_configs(owner: provider, watcher: member_access_some_services).select(:id).map(&:id))
  end

  test 'search filters accessible services only' do
    deleted_service = FactoryBot.create(:simple_service, :with_default_backend_api, account: provider)
    deleted_service.mark_as_deleted!
    [service, deleted_service].each { |service| FactoryBot.create(:proxy_config, proxy: service.proxy, environment: ProxyConfig::ENVIRONMENTS.first) }

    expected_non_deleted_proxy_configs = service.proxy.proxy_configs.select(:id).map(&:id)
    assert_equal expected_non_deleted_proxy_configs, fetch_proxy_configs(owner: provider).select(:id).map(&:id)
  end

  private

  def fetch_proxy_configs(environment: ProxyConfig::ENVIRONMENTS.first, owner: service, **options)
    FetchProxyConfigsService.new(environment: environment, owner: owner, **options).call
  end
end
