module OpenShift
  # Generic Billing provider service interface
  # Currently, this interface is consumed by oo-admin-ctl-usage
  class BillingService
    attr_accessor :log, :error_count, :warning_count
    @oo_billing_provider = OpenShift::BillingService

    def self.provider=(provider_class)
      @oo_billing_provider = provider_class
    end

    def self.instance
      @oo_billing_provider.new
    end

    def initialize
      @log = nil
      @error_count = 0
      @warning_count = 0
    end

    def set_logger(log_file=nil)
      if log_file
        @log = Logger.new(log_file)
        output = log_file
      else
        @log = Logger.new(STDOUT)
        output = "terminal"
      end
      @log.level = Logger::DEBUG
      @log.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime} #{severity}:: #{msg}\n"
      end
      puts "Errors/Warnings will be logged to #{output}"
    end

    # Unique usage id that can be used to narrow down to specific set of records.
    # This will be helpful in debuging.
    def get_uid(urec)
      "User: #{urec['login']}, Gear: #{urec['gear_id']}, UsageType: #{urec['usage_type']}"
    end

    def print_error(msg, urec=nil)
      @error_count += 1
      msg += "(#{get_uid(urec)})" if urec
      @log.error msg
    end

    def print_warning(msg, urec=nil)
      @warning_count += 1
      msg += "(#{get_uid(urec)})" if urec
      @log.warn msg
    end

    def get_provider_name
    end

    def get_plans
    end

    def get_billing_acct_no(user)
    end

    def get_usage_time(billing_acct_no, urec, begin_time, end_time)
      total_time = 0
      if end_time > begin_time
        total_time = (end_time - begin_time) / 3600 #hours
      end
      total_time
    end

    def sync_usage(session, user_usage_records, sync_time)
    end

    # Check UsageRecord and Usage collection consistency
    def check_usage_consistency(session, srec)
      usage = session[:usage].find(login: srec['login'], gear_id: srec['gear_id'],
                                   usage_type: srec['usage_type'], begin_time: srec['time']).first
      unless usage
        print_warning "Record NOT found in Usage collection.", srec
        usage = Usage.new
        usage.login = srec['login']
        usage.gear_id = srec['gear_id']
        usage.usage_type = srec['usage_type']
        usage.app_name = srec['app_name']
        usage.begin_time = srec['time']
        usage.gear_size = srec['gear_size']
        usage.addtl_fs_gb = srec['addtl_fs_gb']
        usage.cart_name = srec['cart_name']
        usage.end_time = srec['end_time'] if srec['ended']
        usage.save!
      else srec['ended'] && usage['end_time'].nil?
        print_warning "End time NOT set in Usage collection.", srec
        session[:usage].find(_id: usage['_id']).update({"$set" => {end_time: srec['end_time']}})
      end
    end
 
    # For ended usage records: delete from mongo
    def delete_ended_urecs(session, srecs)
      return if srecs.empty?
      user_ids = []
      srecs.each do |srec|
        if srec['ended']
          check_usage_consistency(session, srec)
          user_ids << srec['_id']
          user_ids << srec['end_id'] if srec['end_id']
        end
      end
      # Deleting ended usage records
      user_ids.uniq!
      session[:usage_records].find({_id: {"$in" => user_ids}}).remove_all unless user_ids.empty?
    end
  end
end
