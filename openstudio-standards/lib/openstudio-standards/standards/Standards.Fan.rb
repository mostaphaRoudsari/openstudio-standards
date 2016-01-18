
# A variety of fan calculation methods that are the same regardless of fan type.
# These methods are available to FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
module Fan

  # Sets the fan motor efficiency based on the standard.
  # Assumes 65% fan efficiency and 4-pole, enclosed motor.
  #
  # @return [Bool] true if successful, false if not
  def setStandardEfficiency(template, standards)
    
    # Get the max flow rate from the fan.
    maximum_flow_rate_m3_per_s = nil
    if self.maximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = self.maximumFlowRate.get
    elsif self.autosizedMaximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = self.autosizedMaximumFlowRate.get
    else
      OpenStudio::logFree(OpenStudio::Warn, 'openstudio.standards.Fan', "For #{self.name} max flow rate is not hard sized, cannot apply efficiency standard.")
      return false
    end
    
    # Convert max flow rate to cfm
    maximum_flow_rate_cfm = OpenStudio.convert(maximum_flow_rate_m3_per_s, 'm^3/s', 'cfm').get
    
    # Get the pressure rise from the fan
    pressure_rise_pa = self.pressureRise
    pressure_rise_in_h2o = OpenStudio.convert(pressure_rise_pa, 'Pa','inH_{2}O').get
    
    # Get the default impeller efficiency
    fan_impeller_eff = self.baselineImpellerEfficiency(template)
    
    # Calculate the Brake Horsepower
    brake_hp = (pressure_rise_in_h2o * maximum_flow_rate_cfm)/(fan_impeller_eff * 6356) 
    allowed_hp = brake_hp * 1.1 # Per PNNL document #TODO add reference
    if allowed_hp > 0.1
      allowed_hp = allowed_hp.round(2)+0.0001
    elsif allowed_hp < 0.01
      allowed_hp = 0.01
    end
    
    # Minimum motor size for efficiency lookup
    # is 1 HP unless the motor serves an exhaust fan,
    # a powered VAV terminal, or a fan coil unit.
    unless self.is_small_fan
      if allowed_hp < 1.0
        allowed_hp = 1.01
      end
    end
    
    # Find the motor efficiency
    motor_eff = standard_minimum_motor_efficiency(template, standards, allowed_hp)

    # Calculate the total fan efficiency
    total_fan_eff = fan_impeller_eff * motor_eff
    
    # Set the total fan efficiency and the motor efficiency
    if self.to_FanZoneExhaust.is_initialized
      self.setFanEfficiency(total_fan_eff)
    else
      self.setFanEfficiency(total_fan_eff)
      self.setMotorEfficiency(motor_eff)
    end
    
    OpenStudio::logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{self.name}: allowed_hp = #{allowed_hp.round(2)}HP; motor eff = #{(motor_eff*100).round(2)}%; total fan eff = #{(total_fan_eff*100).round}% based on #{maximum_flow_rate_cfm.round} cfm.")
    
    return true
    
  end

  def set_standard_minimum_motor_efficiency(template, standards, allowed_hp)
    
    # Find the motor efficiency
    motor_eff = standard_minimum_motor_efficiency(template, standards, allowed_hp)

    # Change the motor efficiency
    # but preserve the existing fan impeller
    # efficiency.
    self.changeMotorEfficiency(motor_eff)
    
    OpenStudio::logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{self.name}: allowed hp = #{allowed_hp.round(2)}HP; motor eff = #{(motor_eff*100).round(2)}%.")
    
    return true    
  
  end
  
  # Adjust the fan pressure rise to hit the target fan power (W).
  # Keep the fan impeller and motor efficiencies static.
  #
  # @param target_fan_power [Double] the target fan power in W
  # @return [Bool] true if successful, false if not
  def adjust_pressure_rise_to_meet_fan_power(target_fan_power)
  
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = 0
    if self.autosizedMaximumFlowRate.is_initialized
      dsn_air_flow_m3_per_s = self.autosizedMaximumFlowRate.get
    else
      dsn_air_flow_m3_per_s = self.maximumFlowRate.get
    end  
  
    # Get the current fan power
    current_fan_power_w = self.fanPower

    # Get the current pressure rise (Pa)
    pressure_rise_pa = self.pressureRise
    
    # Get the total fan efficiency
    fan_total_eff = self.fanEfficiency

    # Calculate the new fan pressure rise (Pa)
    new_pressure_rise_pa = target_fan_power * fan_total_eff / dsn_air_flow_m3_per_s
    new_pressure_rise_in_h2o = OpenStudio.convert(new_pressure_rise_pa, 'Pa','inH_{2}O').get
    
    # Set the new pressure rise
    self.setPressureRise(new_pressure_rise_pa)
    
    # Calculate the new power
    new_power_w = self.fanPower
    
    OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Fan", "For #{self.name}, new pressure rise = #{new_pressure_rise_in_h2o.round(1)} in w.c., new power = #{new_power_w.round} W.")
    
    return true
  
  end
  
  # Determines the fan power (W) based on 
  # flow rate, pressure rise, and total fan efficiency(impeller eff * motor eff) 
  # 
  # @return [Double] fan power
  #   @units Watts (W)
  def fanPower()
    
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = 0
    if self.autosizedMaximumFlowRate.is_initialized
      dsn_air_flow_m3_per_s = self.autosizedMaximumFlowRate.get
    else
      dsn_air_flow_m3_per_s = self.maximumFlowRate.get
    end
  
    # Get the total fan efficiency
    fan_total_eff = self.fanEfficiency
    
    # Get the pressure rise (Pa)
    pressure_rise_pa = self.pressureRise
    
    # Calculate the fan power (W)
    fan_power_w = pressure_rise_pa * dsn_air_flow_m3_per_s / fan_total_eff
    
    return fan_power_w
  
  end

  # Determines the brake horsepower of the fan
  # based on fan power and fan motor efficiency.
  # 
  # @return [Double] brake horsepower
  #   @units horsepower (hp)  
  def brakeHorsepower()
  
    # Get the fan motor efficiency
    existing_motor_eff = 0.7
    if self.to_FanZoneExhaust.empty?
      existing_motor_eff = self.motorEfficiency
    end
  
    # Get the fan power (W)
    fan_power_w = self.fanPower
    
    # Calculate the brake horsepower (bhp)
    fan_bhp = fan_power_w * existing_motor_eff / 746
    
    return fan_bhp

  end

  # Changes the fan motor efficiency and also the fan total efficiency
  # at the same time, preserving the impeller efficiency.
  #
  # @param motor_eff [Double] motor efficiency (0.0 to 1.0)
  def changeMotorEfficiency(motor_eff)
    
    # Calculate the existing impeller efficiency
    existing_motor_eff = 0.7
    if self.to_FanZoneExhaust.empty?
      existing_motor_eff = self.motorEfficiency
    end
    existing_total_eff = self.fanEfficiency
    existing_impeller_eff = existing_total_eff / existing_motor_eff
    
    # Calculate the new total efficiency
    new_total_eff = motor_eff * existing_impeller_eff
    
    # Set the revised motor and total fan efficiencies
    if self.to_FanZoneExhaust.is_initialized
      self.setFanEfficiency(new_total_eff)
    else
      self.setFanEfficiency(new_total_eff)
      self.setMotorEfficiency(motor_eff)
    end
  
  end

  # Changes the fan impeller efficiency and also the fan total efficiency
  # at the same time, preserving the motor efficiency.
  #
  # @param impeller_eff [Double] impeller efficiency (0.0 to 1.0)  
  def changeImpellerEfficiency(impeller_eff)
    
    # Get the existing motor efficiency
    existing_motor_eff = 0.7
    if self.to_FanZoneExhaust.empty?
      existing_motor_eff = self.motorEfficiency
    end

    # Calculate the new total efficiency
    new_total_eff = existing_motor_eff * impeller_eff
    
    # Set the revised motor and total fan efficiencies
    self.setFanEfficiency(new_total_eff)
  
  end
  
  # Determines the baseline fan impeller efficiency
  # based on the specified fan type.
  #
  # @return [Double] impeller efficiency (0.0 to 1.0)
  # @todo Add fan type to data model and modify this method
  def baselineImpellerEfficiency(template)
  
    # Assume that the fan efficiency is 65% for normal fans
    # and 55% for small fans (like exhaust fans).
    # TODO add fan type to fan data model
    # and infer impeller efficiency from that?
    # or do we always assume a certain type of
    # fan impeller for the baseline system?
    # TODO check COMNET and T24 ACM and PNNL 90.1 doc
    fan_impeller_eff = 0.65
  
    if self.is_small_fan
      fan_impeller_eff = 0.55
    end

    return fan_impeller_eff
  
  end
  
  # Determines the minimum fan motor efficiency 
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method
  #
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Double] minimum motor efficiency (0.0 to 1.0)
  def standard_minimum_motor_efficiency(template, standards, motor_bhp)
  
    fan_motor_eff = 0.85
  
    # Lookup the minimum motor efficiency
    motors = standards["motors"]
    
    # Assuming all fan motors are 4-pole ODP
    search_criteria = {
      "template" => template,
      "number_of_poles" => 4.0,
      "type" => "Enclosed",
    }
    
    motor_properties = self.model.find_object(motors, search_criteria, motor_bhp)
    if motor_properties.nil?
      OpenStudio::logFree(OpenStudio::Error, "openstudio.standards.Fan", "For #{self.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
      return fan_motor_eff
    end
 
    fan_motor_eff = motor_properties["nominal_full_load_efficiency"]  

    # Add exception for small 
    
    
    
    return fan_motor_eff
  
  end

  # Zone exhaust fans, fan coil unit fans,
  # and powered VAV terminal fans all count
  # as small fans and get different impeller efficiencies
  # and motor efficiencies than other fans
  # @return [Bool] returns true if it is a small fan, false if not
  def is_small_fan()
  
    is_small = false

    # Exhaust fan
    if self.to_FanZoneExhaust.is_initialized
      is_small = true
    # Fan coil unit
    elsif self.containingZoneHVACComponent.is_initialized
      zone_hvac = self.containingZoneHVACComponent.get
      if zone_hvac.to_ZoneHVACFourPipeFanCoil.is_initialized
        is_small = true
      end
    # Powered VAV terminal
    elsif self.containingHVACComponent.is_initialized
      zone_hvac = self.containingHVACComponent.get
      if zone_hvac.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized || zone_hvac.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized
        is_small = true
      end
    end  
  
    return is_small
  
  end
  
end
