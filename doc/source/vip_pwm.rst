##################################################################################################################################
P2L2 VIP PWM
##################################################################################################################################

**Quick Access**

* `BFM`_

  * :ref:`pwm_generate_bfm`
  * :ref:`pwm_drive_period_bfm`
  * :ref:`pwm_drive_idle_bfm`
  * :ref:`pwm_measure_bfm`
  * :ref:`pwm_check_bfm`
  * :ref:`pwm_check_duty_bfm`
  * :ref:`pwm_conversion_functions_bfm`

* `VVC`_

  * :ref:`pwm_generate_vvc`
  * :ref:`pwm_start_vvc`
  * :ref:`pwm_update_vvc`
  * :ref:`pwm_stop_vvc`
  * :ref:`pwm_abort_vvc`
  * :ref:`pwm_measure_vvc`
  * :ref:`pwm_check_vvc`
  * :ref:`pwm_check_duty_vvc`

The PWM VIP generates, measures and checks a single pulse-width modulated (PWM) line: a periodic signal with period T and
active time t_on (duty cycle D = t_on/T). See :ref:`pwm_additional_doc` for the waveform definition.

**********************************************************************************************************************************
BFM
**********************************************************************************************************************************
BFM functionality is implemented in pwm_bfm_pkg.vhd

.. _t_pwm_types:

Types
==================================================================================================================================
+------------------------------+--------------------------------------------------------------------------------------------------+
| Type                         | Values                                                                                           |
+==============================+==================================================================================================+
| t_pwm_role                   | GENERATOR, OBSERVER. Role of a VVC instance, see :ref:`pwm_roles`.                               |
+------------------------------+--------------------------------------------------------------------------------------------------+
| t_pwm_polarity               | ACTIVE_HIGH, ACTIVE_LOW. Level of the active part of the period.                                 |
+------------------------------+--------------------------------------------------------------------------------------------------+
| t_pwm_alignment              | LEFT_ALIGNED, RIGHT_ALIGNED, CENTER_ALIGNED. Position of the pulse within the period, see        |
|                              | :ref:`pwm_waveform`.                                                                             |
+------------------------------+--------------------------------------------------------------------------------------------------+
| t_pwm_idle_level             | IDLE_INACTIVE, IDLE_ACTIVE, IDLE_HIGH_Z. Line level when no waveform is generated.               |
+------------------------------+--------------------------------------------------------------------------------------------------+

.. _t_pwm_measurement:

**t_pwm_measurement**

Result of :ref:`pwm_measure_bfm`. Default value (also the result after a missing-activity alert or a terminate) is C_PWM_MEASUREMENT_DEFAULT.

+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| Record element               | Type                         | Default         | Description                                     |
+==============================+==============================+=================+=================================================+
| period                       | time                         | 0 ns            | Active-going edge to active-going edge. 0 ns    |
|                              |                              |                 | when is_constant.                               |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| active_time                  | time                         | 0 ns            | Active-going edge to inactive-going edge. 0 ns  |
|                              |                              |                 | when is_constant.                               |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| duty_cycle                   | real                         | 0.0             | active_time / period. 0.0 or 1.0 when           |
|                              |                              |                 | is_constant.                                    |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| is_constant                  | boolean                      | false           | No edge within the timeout before the first     |
|                              |                              |                 | active-going edge: the line held constant_level |
|                              |                              |                 | (0 % or 100 %).                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| constant_level               | std_logic                    | 'U'             | Line level when is_constant ('0', '1', or 'Z'   |
|                              |                              |                 | with IDLE_HIGH_Z), else 'U'                     |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+

.. _t_pwm_bfm_config:

Configuration Record
==================================================================================================================================
**t_pwm_bfm_config**

Default value for the record is C_PWM_BFM_CONFIG_DEFAULT.

+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| Record element               | Type                         | Default         | Description                                     |
+==============================+==============================+=================+=================================================+
| polarity                     | :ref:`t_pwm_polarity         | ACTIVE_HIGH     | Active level of the line. Generation and        |
|                              | <t_pwm_types>`               |                 | observation.                                    |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| alignment                    | :ref:`t_pwm_alignment        | LEFT_ALIGNED    | Position of the pulse within the period.        |
|                              | <t_pwm_types>`               |                 | Generation only.                                |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| idle_level                   | :ref:`t_pwm_idle_level       | IDLE_INACTIVE   | Line level when no waveform is generated. With  |
|                              | <t_pwm_types>`               |                 | IDLE_HIGH_Z, an observer tolerates 'Z' before   |
|                              |                              |                 | the first active-going edge.                    |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| jitter                       | time                         | 0 ns            | Maximum random offset of each generated edge,   |
|                              |                              |                 | see :ref:`pwm_jitter`. 0 ns disables jitter, <  |
|                              |                              |                 | 0 ns gives a TB_ERROR. Generation only.         |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| jitter_seed1                 | positive                     | C_RAND_INIT_SE\ | Seed of the jitter randomization. Every         |
|                              |                              | ED_1            | pwm_generate() call and every VVC run starts    |
|                              |                              |                 | from the seeds, so a run is reproducible.       |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| jitter_seed2                 | positive                     | C_RAND_INIT_SE\ | Second seed of the jitter randomization         |
|                              |                              | ED_2            |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| period_tolerance             | time                         | 0 ns            | Absolute tolerance on the checked period        |
|                              |                              |                 | (inclusive). Observation.                       |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| active_time_tolerance        | time                         | 0 ns            | Absolute tolerance on the checked active time   |
|                              |                              |                 | (inclusive). Observation.                       |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| duty_tolerance               | real                         | 0.0             | Absolute tolerance on the checked duty cycle    |
|                              |                              |                 | (inclusive), 0.0 to 1.0. Observation.           |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| duty_rounding_margin         | real                         | 1.0e-12         | Added to duty_tolerance against real rounding,  |
|                              |                              |                 | e.g. 0.26 - 0.25 > 0.01 in reals. Must be >=    |
|                              |                              |                 | 0.0. Observation.                               |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| min_pulse_width              | time                         | 0 ns            | Pulses or gaps shorter than this raise an alert |
|                              |                              |                 | (glitch). 0 ns disables the check. Observation. |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| timeout                      | time                         | C_UNDEFINED_TI\ | Maximum wait for each required edge, see        |
|                              |                              | ME              | :ref:`pwm_timeout`. C_UNDEFINED_TIME = not set, |
|                              |                              |                 | 0 ns = no timeout. Observation.                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| timeout_severity             | :ref:`t_alert_level`         | ERROR           | Alert level of a missing-activity timeout.      |
|                              |                              |                 | Observation.                                    |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| id_for_bfm                   | :ref:`t_msg_id               | ID_BFM          | Message ID used for logging general messages in |
|                              | <message_ids>`               |                 | the BFM                                         |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| id_for_bfm_wait              | :ref:`t_msg_id               | ID_BFM_WAIT     | Message ID used for logging waits in the BFM    |
|                              | <message_ids>`               |                 |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+

Methods
==================================================================================================================================
* All signals are active high unless config.polarity is ACTIVE_LOW.
* All parameters in brackets are optional.
* Invalid parameters raise a TB_ERROR alert. The procedure then returns without using time or changing the line.

.. _pwm_generate_bfm:

pwm_generate()
----------------------------------------------------------------------------------------------------------------------------------
Generates num_periods complete periods on the line, then drives the idle level. The procedure returns at the end of the
last period. The duty cycle is given as active time, as ratio or as counter value. The first period starts at the call.
0 ns and period as active time give a constant level without edges (0 % and 100 %).

.. code-block::

    pwm_generate(period, active_time, num_periods, msg, pwm, [scope, [msg_id_panel, [config]]])
    pwm_generate(period, duty, num_periods, msg, pwm, [scope, [msg_id_panel, [config]]])
    pwm_generate(period, count, resolution, num_periods, msg, pwm, [scope, [msg_id_panel, [config]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| constant | period             | in     | time                         | The PWM period T. Must be > 0 ns.                       |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The active time t_on. Must be within 0 ns to period.    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | duty               | in     | real                         | Duty cycle as ratio 0.0 to 1.0, converted to an active  |
|          |                    |        |                              | time rounded to the nearest simulator resolution unit   |
|          |                    |        |                              | (half a unit is rounded up).                            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | count              | in     | integer                      | Duty cycle as counter value, 0 to resolution            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | resolution         | in     | integer                      | Number of counter steps of the period, >= 1             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of complete periods to generate, >= 1            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | pwm                | inout  | std_logic                    | The PWM line driven by the BFM                          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_BFM_SCOPE ("PWM BFM").   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg_id_panel       | in     | t_msg_id_panel               | Controls verbosity within a specified scope. Default    |
|          |                    |        |                              | value is shared_msg_id_panel. For more information see  |
|          |                    |        |                              | :ref:`vvc_framework_verbosity_ctrl`.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior and restrictions. Default |
|          |                    |        | <t_pwm_bfm_config>`          | value is C_PWM_BFM_CONFIG_DEFAULT.                      |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_generate(1 us, 250 ns, 10, "10 periods with 25 % duty", pwm, C_SCOPE, shared_msg_id_panel, C_PWM_BFM_CONFIG_DEFAULT);
    pwm_generate(1 us, 0.25, 10, "10 periods with 25 % duty", pwm, C_SCOPE, shared_msg_id_panel, C_PWM_BFM_CONFIG_DEFAULT);
    pwm_generate(1 us, 64, 256, 10, "10 periods with 64/256 duty", pwm, C_SCOPE, shared_msg_id_panel, C_PWM_BFM_CONFIG_DEFAULT);

    -- With the default values of the optional parameters:
    pwm_generate(1 us, 0.25, 10, "10 periods with 25 % duty", pwm);


.. _pwm_drive_period_bfm:

pwm_drive_period()
----------------------------------------------------------------------------------------------------------------------------------
Drives one complete period according to config.polarity, config.alignment and config.jitter and returns at the end of
the period. This is the timing core used by pwm_generate() and the VVC. The parameters are not checked: they must be
valid (period > 0 ns, 0 ns <= active_time <= period, config.jitter >= 0 ns). The jitter seeds are passed as variables, so
consecutive calls continue the random sequence.

The overload with 'abort' returns at once with aborted = true when 'abort' has an event during the period. The line then
keeps its level; the caller drives the idle level.

.. code-block::

    pwm_drive_period(period, active_time, pwm, config, seed1, seed2)
    pwm_drive_period(period, active_time, pwm, config, seed1, seed2, abort, aborted)

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| constant | period             | in     | time                         | The PWM period T. Must be > 0 ns.                       |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The active time t_on. Must be within 0 ns to period.    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | pwm                | inout  | std_logic                    | The PWM line driven by the BFM                          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior                           |
|          |                    |        | <t_pwm_bfm_config>`          |                                                         |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| variable | seed1              | inout  | positive                     | Jitter seed, updated by the call                        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| variable | seed2              | inout  | positive                     | Jitter seed, updated by the call                        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | abort              | in     | boolean                      | Optional (overload). An event ends the period at once.  |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| variable | aborted            | out    | boolean                      | Optional (overload). True if the period was ended by    |
|          |                    |        |                              | 'abort'.                                                |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    v_seed1 := C_PWM_BFM_CONFIG_DEFAULT.jitter_seed1;
    v_seed2 := C_PWM_BFM_CONFIG_DEFAULT.jitter_seed2;
    pwm_drive_period(1 us, 500 ns, pwm, C_PWM_BFM_CONFIG_DEFAULT, v_seed1, v_seed2);


.. _pwm_drive_idle_bfm:

pwm_drive_idle()
----------------------------------------------------------------------------------------------------------------------------------
Drives the idle level given by config.idle_level and config.polarity. Use it at time 0 in a BFM-only testbench, as
pwm_generate() only drives the idle level after the last period.

.. code-block::

    pwm_drive_idle(pwm, [config])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | pwm                | inout  | std_logic                    | The PWM line driven by the BFM                          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior and restrictions. Default |
|          |                    |        | <t_pwm_bfm_config>`          | value is C_PWM_BFM_CONFIG_DEFAULT.                      |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_drive_idle(pwm, C_PWM_BFM_CONFIG_DEFAULT);


.. _pwm_measure_bfm:

pwm_measure()
----------------------------------------------------------------------------------------------------------------------------------
Measures one complete period and returns the result in a :ref:`t_pwm_measurement <t_pwm_measurement>` record. The
measurement starts at the first active-going edge after the call; a period in progress is ignored.

* If the line does not change before the first active-going edge for the timeout, the result is the constant level
  (is_constant = true, duty_cycle 0.0 or 1.0). This is a result, not an alert.
* A timeout after the first active-going edge raises a missing-activity alert with severity config.timeout_severity and
  returns C_PWM_MEASUREMENT_DEFAULT.
* Invalid levels and pulses or gaps shorter than config.min_pulse_width raise an ERROR alert.
* The timeout must be set, per call or in config.timeout, otherwise a TB_ERROR is raised (there is no period to derive it
  from).

.. code-block::

    pwm_measure(result, msg, pwm, [terminate,] [timeout, [scope, [msg_id_panel, [config]]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| variable | result             | out    | :ref:`t_pwm_measurement      | The measured period, active time and duty cycle         |
|          |                    |        | <t_pwm_measurement>`         |                                                         |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | pwm                | in     | std_logic                    | The PWM line observed by the BFM                        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | terminate          | in     | std_logic                    | Optional (overload). '1' ends the observation at once,  |
|          |                    |        |                              | without an alert (logged with ID_TERMINATE_CMD). Used   |
|          |                    |        |                              | by the VVC for terminate_current_command().             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_BFM_SCOPE ("PWM BFM").   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg_id_panel       | in     | t_msg_id_panel               | Controls verbosity within a specified scope. Default    |
|          |                    |        |                              | value is shared_msg_id_panel. For more information see  |
|          |                    |        |                              | :ref:`vvc_framework_verbosity_ctrl`.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior and restrictions. Default |
|          |                    |        | <t_pwm_bfm_config>`          | value is C_PWM_BFM_CONFIG_DEFAULT.                      |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_measure(v_result, "Measure the PWM output", pwm, 2 us, C_SCOPE, shared_msg_id_panel, C_PWM_BFM_CONFIG_DEFAULT);

    -- With the default values of the optional parameters:
    pwm_measure(v_result, "Measure the PWM output", pwm, 2 us);


.. _pwm_check_bfm:

pwm_check()
----------------------------------------------------------------------------------------------------------------------------------
Checks num_periods consecutive periods against the expected period and active time, within config.period_tolerance
and config.active_time_tolerance (inclusive).

* If all periods match, a log message is written with ID config.id_for_bfm.
* Each failing period raises one alert with severity 'alert_level', naming the period index and the measured and expected
  values with the tolerance.
* active_time = 0 ns or = period checks that the line holds the inactive or active level for the timeout (the
  observation window, which must then be > 0 ns). A wrong level or a change in the window raises one alert.
* A missing edge raises a missing-activity alert with severity config.timeout_severity and ends the check.
* If neither the call nor config.timeout sets the timeout, 2 * period is used.

.. code-block::

    pwm_check(period, active_time, num_periods, msg, pwm, [terminate,] [alert_level, [timeout, [scope, [msg_id_panel, [config]]]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| constant | period             | in     | time                         | The expected period. Must be > 0 ns.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The expected active time, 0 ns to period                |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of consecutive periods to check, >= 1            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | pwm                | in     | std_logic                    | The PWM line observed by the BFM                        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | terminate          | in     | std_logic                    | Optional (overload). '1' ends the observation at once,  |
|          |                    |        |                              | without an alert (logged with ID_TERMINATE_CMD). Used   |
|          |                    |        |                              | by the VVC for terminate_current_command().             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | alert_level        | in     | :ref:`t_alert_level`         | Sets the severity for the alert. Default value is       |
|          |                    |        |                              | ERROR.                                                  |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_BFM_SCOPE ("PWM BFM").   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg_id_panel       | in     | t_msg_id_panel               | Controls verbosity within a specified scope. Default    |
|          |                    |        |                              | value is shared_msg_id_panel. For more information see  |
|          |                    |        |                              | :ref:`vvc_framework_verbosity_ctrl`.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior and restrictions. Default |
|          |                    |        | <t_pwm_bfm_config>`          | value is C_PWM_BFM_CONFIG_DEFAULT.                      |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_check(1 us, 250 ns, 5, "Check 5 periods", pwm, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, C_PWM_BFM_CONFIG_DEFAULT);

    -- With the default values of the optional parameters:
    pwm_check(1 us, 250 ns, 5, "Check 5 periods", pwm);


.. _pwm_check_duty_bfm:

pwm_check_duty()
----------------------------------------------------------------------------------------------------------------------------------
Checks the duty cycle of num_periods consecutive periods within config.duty_tolerance (inclusive, plus
config.duty_rounding_margin), independent of the period. Each failing period raises one alert with severity
'alert_level'. duty = 0.0 or 1.0 checks for a constant level as pwm_check(). The timeout must be set, per call or in
config.timeout.

.. code-block::

    pwm_check_duty(duty, num_periods, msg, pwm, [terminate,] [alert_level, [timeout, [scope, [msg_id_panel, [config]]]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| constant | duty               | in     | real                         | The expected duty cycle, 0.0 to 1.0                     |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of consecutive periods to check, >= 1            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | pwm                | in     | std_logic                    | The PWM line observed by the BFM                        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| signal   | terminate          | in     | std_logic                    | Optional (overload). '1' ends the observation at once,  |
|          |                    |        |                              | without an alert (logged with ID_TERMINATE_CMD). Used   |
|          |                    |        |                              | by the VVC for terminate_current_command().             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | alert_level        | in     | :ref:`t_alert_level`         | Sets the severity for the alert. Default value is       |
|          |                    |        |                              | ERROR.                                                  |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_BFM_SCOPE ("PWM BFM").   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg_id_panel       | in     | t_msg_id_panel               | Controls verbosity within a specified scope. Default    |
|          |                    |        |                              | value is shared_msg_id_panel. For more information see  |
|          |                    |        |                              | :ref:`vvc_framework_verbosity_ctrl`.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | config             | in     | :ref:`t_pwm_bfm_config       | Configuration of BFM behavior and restrictions. Default |
|          |                    |        | <t_pwm_bfm_config>`          | value is C_PWM_BFM_CONFIG_DEFAULT.                      |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_check_duty(0.25, 10, "Check 25 % duty", pwm, ERROR, 2 us, C_SCOPE, shared_msg_id_panel, v_config);


.. _pwm_conversion_functions_bfm:

Conversion functions
----------------------------------------------------------------------------------------------------------------------------------
The BFM package also provides the functions used by the procedures above:


+------------------------------------------------------------------+--------------------------------------------------------------+
| Function                                                         | Description                                                  |
+==================================================================+==============================================================+
| pwm_duty_to_active_time(duty, period) return time                | duty * period, rounded to the nearest simulator resolution   |
|                                                                  | unit (half a unit is rounded up). Requires 0.0 <= duty <=    |
|                                                                  | 1.0 and period > 0 ns.                                       |
+------------------------------------------------------------------+--------------------------------------------------------------+
| pwm_count_to_active_time(count, resolution, period) return time  | (count / resolution) * period, rounded as                    |
|                                                                  | pwm_duty_to_active_time(). Requires 0 <= count <=            |
|                                                                  | resolution.                                                  |
+------------------------------------------------------------------+--------------------------------------------------------------+
| pwm_active_level(config) return std_logic                        | '1' for ACTIVE_HIGH, '0' for ACTIVE_LOW                      |
+------------------------------------------------------------------+--------------------------------------------------------------+
| pwm_inactive_level(config) return std_logic                      | The opposite of pwm_active_level()                           |
+------------------------------------------------------------------+--------------------------------------------------------------+
| pwm_idle_value(config) return std_logic                          | The value driven on the line when idle ('Z' for IDLE_HIGH_Z) |
+------------------------------------------------------------------+--------------------------------------------------------------+

Local BFM overloads
==================================================================================================================================
All optional parameters of the PWM BFM procedures have default values, so a call with the key parameters only uses
C_BFM_SCOPE, shared_msg_id_panel and C_PWM_BFM_CONFIG_DEFAULT, e.g. ::

    pwm_check(1 us, 250 ns, 5, "Check 5 periods", pwm);

A good approach for better readability and maintainability, when the testbench uses its own configuration or scope, is to
make simple, local overloads for the BFM procedures in the TB process. A local overload with the same parameters as the
call above would be ambiguous, because the BFM procedure matches the call through its default values. Leave out the
signal instead, which the local procedure can read directly, e.g. ::

    pwm_check(1 us, 250 ns, 5, "Check 5 periods");

rather than ::

    pwm_check(1 us, 250 ns, 5, "Check 5 periods", pwm, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, C_PWM_CONFIG_LOCAL);

By defining the local overload as e.g. ::

    procedure pwm_check(
      constant period      : in time;
      constant active_time : in time;
      constant num_periods : in integer;
      constant msg         : in string) is
    begin
      pwm_check(period,               -- Keep as is
                active_time,          -- Keep as is
                num_periods,          -- Keep as is
                msg,                  -- Keep as is
                pwm,                  -- The TB signal
                ERROR,                -- Use the default
                C_UNDEFINED_TIME,     -- Use the timeout from the config
                C_SCOPE,              -- Use the TB scope
                shared_msg_id_panel,  -- Use global, shared msg_id_panel
                C_PWM_CONFIG_LOCAL);  -- Use locally defined configuration
    end procedure;

Using a local overload like this also allows the following – if wanted:

* Set up defaults for constants. May be different for two overloads of the same BFM
* Apply dedicated message ID panel to allow dedicated verbosity control

.. note::

    The generation procedures drive the signal, so a local overload of pwm_generate() without the signal parameter must be
    declared in the process that drives the signal.


Compilation
==================================================================================================================================
.. include:: rst_snippets/bfm_compilation.rst

Simulator compatibility and setup
----------------------------------------------------------------------------------------------------------------------------------
.. include:: rst_snippets/simulator_compatibility.rst

The PWM BFM computes edge times in simulator resolution units (std.env.resolution_limit). Waveforms with sub-ns times
need a finer resolution than the Questa default of 1 ns, e.g. ``vsim -t ps``.

.. _pwm_additional_doc:

Additional Documentation
==================================================================================================================================
.. _pwm_waveform:

Waveform
----------------------------------------------------------------------------------------------------------------------------------
A period of length T contains one active pulse of length t_on and one inactive interval t_off = T - t_on. The alignment
sets where the pulse sits within the period:


+------------------------------+--------------------------------------------------------------------------------------------------+
| Alignment                    | Waveform within one period [0, T)                                                                |
+==============================+==================================================================================================+
| LEFT_ALIGNED (default)       | Active during [0, t_on), inactive during [t_on, T)                                               |
+------------------------------+--------------------------------------------------------------------------------------------------+
| RIGHT_ALIGNED                | Inactive during [0, t_off), active during [t_off, T)                                             |
+------------------------------+--------------------------------------------------------------------------------------------------+
| CENTER_ALIGNED               | Inactive during [0, t_off/2), active for t_on, then inactive for the rest. If t_off is odd in    |
|                              | resolution units, the extra unit goes to the second inactive interval.                           |
+------------------------------+--------------------------------------------------------------------------------------------------+

* t_on = 0 ns (0 %) and t_on = T (100 %) give a constant inactive or active level without edges. Switching between these
  and other duty cycles gives no glitches.
* Times given as duty or count/resolution are rounded to the nearest simulator resolution unit, half a unit up.
* An observer measures T from active-going edge to active-going edge and t_on from the active-going to the inactive-going
  edge. It cannot tell alignments apart from a constant waveform.


.. _pwm_jitter:

Jitter
----------------------------------------------------------------------------------------------------------------------------------
With config.jitter = j > 0 ns, every generated edge is moved by a random offset in [-j, +j] from its ideal time. The
offsets do not accumulate, so the mean period stays T. Edges are never reordered, every pulse and gap stays at least one
resolution unit long, and an edge at the start of a period is not moved before the period start (so these edges only
move later). The randomization starts from config.jitter_seed1/2 in every pwm_generate() call and every VVC run, so a
run with the same seeds is reproducible. 0 % and 100 % are not affected.


.. _pwm_timeout:

Observation rules and timeout
----------------------------------------------------------------------------------------------------------------------------------
* The timeout applies to each required edge: counted from the call for the first edge, and from the previous edge after
  that. A check of many periods therefore does not need a long timeout.
* A per-call timeout overrides config.timeout. If neither is set, pwm_check() uses 2 * period; pwm_measure() and
  pwm_check_duty() raise a TB_ERROR. 0 ns means no timeout; a negative timeout gives a TB_ERROR.
* An edge is a change between '0' and '1'. Any other value raises an alert each time the line changes to it; an invalid
  value that returns to the same level is no edge. Before the first active-going edge, 'Z' is tolerated with
  IDLE_HIGH_Z.
* Alert levels: pwm_measure() uses ERROR, the checks use 'alert_level', a missing-activity timeout uses
  config.timeout_severity.

.. important::

    * This VIP is not a complete PWM protocol checker, only the listed checks are made.
    * Out of scope: complementary outputs and dead time, multi-phase PWM, mid-period updates, phase-correct counter modes,
      randomised PWM as a protocol mode (only the bounded jitter above), analogue effects and PDM.


**********************************************************************************************************************************
VVC
**********************************************************************************************************************************
* VVC functionality is implemented in pwm_vvc.vhd
* For general information see :ref:`vvc_framework_vvc_mechanisms_and_features`.

Entity
==================================================================================================================================

Generics
----------------------------------------------------------------------------------------------------------------------------------

+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| Name                         | Type                         | Default         | Description                                     |
+==============================+==============================+=================+=================================================+
| GC_INSTANCE_IDX              | natural                      | 1               | Instance number to assign the VVC. Maximum      |
|                              |                              |                 | value is defined by C_PWM_VVC_MAX_INSTANCE_NUM  |
|                              |                              |                 | in adaptations_pkg.                             |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_ROLE                      | :ref:`t_pwm_role             | GENERATOR       | Role of the VVC instance, fixed at elaboration. |
|                              | <t_pwm_types>`               |                 | See :ref:`pwm_roles`.                           |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_PWM_BFM_CONFIG            | :ref:`t_pwm_bfm_config       | C_PWM_BFM_CONF\ | Configuration for the PWM BFM. A generator      |
|                              | <t_pwm_bfm_config>`          | IG_DEFAULT      | drives the idle level given by this             |
|                              |                              |                 | configuration from time 0.                      |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_CMD_QUEUE_COUNT_MAX       | natural                      | C_CMD_QUEUE_CO\ | Absolute maximum number of commands in the VVC  |
|                              |                              | UNT_MAX         | command queue                                   |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_CMD_QUEUE_COUNT_THRESHOLD | natural                      | C_CMD_QUEUE_CO\ | An alert will be generated when reaching this   |
|                              |                              | UNT_THRESHOLD   | threshold to indicate that the command queue is |
|                              |                              |                 | almost full. The queue will still accept new    |
|                              |                              |                 | commands until it reaches                       |
|                              |                              |                 | GC_CMD_QUEUE_COUNT_MAX.                         |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_CMD_QUEUE_COUNT_THRESHOL\ | :ref:`t_alert_level`         | C_CMD_QUEUE_CO\ | Alert severity which will be used when command  |
| D_SEVERITY                   |                              | UNT_THRESHOLD\  | queue reaches GC_CMD_QUEUE_COUNT_THRESHOLD      |
|                              |                              | _SEVERITY       |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_RESULT_QUEUE_COUNT_MAX    | natural                      | C_RESULT_QUEUE\ | Maximum number of unfetched results before      |
|                              |                              | _COUNT_MAX      | result_queue is full                            |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_RESULT_QUEUE_COUNT_THRES\ | natural                      | C_RESULT_QUEUE\ | An alert will be issued if result queue exceeds |
| HOLD                         |                              | _COUNT_THRESHO\ | this count. Used for early warning if result    |
|                              |                              | LD              | queue is almost full. Will be ignored if set to |
|                              |                              |                 | 0.                                              |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| GC_RESULT_QUEUE_COUNT_THRES\ | :ref:`t_alert_level`         | C_RESULT_QUEUE\ | Severity of alert to be initiated if exceeding  |
| HOLD_SEVERITY                |                              | _COUNT_THRESHO\ | GC_RESULT_QUEUE_COUNT_THRESHOLD                 |
|                              |                              | LD_SEVERITY     |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+

.. note::

    Default values for the cmd/result queue generics are defined in adaptations_pkg.

Signals
----------------------------------------------------------------------------------------------------------------------------------

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | pwm_vvc_if         | inout  | std_logic                    | The PWM line. Default value 'Z'.                        |
|          |                    |        |                              |                                                         |
|          |                    |        |                              | GENERATOR: driven with the idle level from time 0 and   |
|          |                    |        |                              | with the waveform.                                      |
|          |                    |        |                              |                                                         |
|          |                    |        |                              | OBSERVER: always driven 'Z' and only read, so a         |
|          |                    |        |                              | generator and observers can share one line.             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

Configuration Record
==================================================================================================================================
**vvc_config** accessible via **shared_pwm_vvc_config**

+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| Record element               | Type                         | Default         | Description                                     |
+==============================+==============================+=================+=================================================+
| inter_bfm_delay              | :ref:`t_inter_bfm_delay`     | C_PWM_INTER_BF\ | Delay between any requested BFM accesses        |
|                              |                              | M_DELAY_DEFAULT | towards the DUT. Applies to pwm_generate(),     |
|                              |                              |                 | pwm_start() and the observer commands.          |
|                              |                              |                 |                                                 |
|                              |                              |                 | TIME_START2START: Time from a BFM start to the  |
|                              |                              |                 | next BFM start (a TB_WARNING will be issued if  |
|                              |                              |                 | access takes longer than TIME_START2START).     |
|                              |                              |                 |                                                 |
|                              |                              |                 | TIME_FINISH2START: Time from a BFM end to the   |
|                              |                              |                 | next BFM start.                                 |
|                              |                              |                 |                                                 |
|                              |                              |                 | Any insert_delay() command will add to the      |
|                              |                              |                 | above minimum delays, giving for instance the   |
|                              |                              |                 | ability to skew the BFM starting time.          |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| cmd_queue_count_max          | natural                      | C_CMD_QUEUE_CO\ | Maximum pending number in command queue before  |
|                              |                              | UNT_MAX         | queue is full. Adding additional commands will  |
|                              |                              |                 | result in an ERROR.                             |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| cmd_queue_count_threshold    | natural                      | C_CMD_QUEUE_CO\ | An alert will be issued if command queue        |
|                              |                              | UNT_THRESHOLD   | exceeds this count. Used for early warning if   |
|                              |                              |                 | command queue is almost full. Will be ignored   |
|                              |                              |                 | if set to 0.                                    |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| cmd_queue_count_threshold_s\ | :ref:`t_alert_level`         | C_CMD_QUEUE_CO\ | Severity of alert to be initiated if exceeding  |
| everity                      |                              | UNT_THRESHOLD\  | cmd_queue_count_threshold                       |
|                              |                              | _SEVERITY       |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| result_queue_count_max       | natural                      | C_RESULT_QUEUE\ | Maximum number of unfetched results before      |
|                              |                              | _COUNT_MAX      | result_queue is full                            |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| result_queue_count_threshold | natural                      | C_RESULT_QUEUE\ | An alert will be issued if result queue exceeds |
|                              |                              | _COUNT_THRESHO\ | this count. Used for early warning if result    |
|                              |                              | LD              | queue is almost full. Will be ignored if set to |
|                              |                              |                 | 0.                                              |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| result_queue_count_threshol\ | :ref:`t_alert_level`         | C_RESULT_QUEUE\ | Severity of alert to be initiated if exceeding  |
| d_severity                   |                              | _COUNT_THRESHO\ | result_queue_count_threshold                    |
|                              |                              | LD_SEVERITY     |                                                 |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| bfm_config                   | :ref:`t_pwm_bfm_config       | C_PWM_BFM_CONF\ | Configuration for the PWM BFM. A generator      |
|                              | <t_pwm_bfm_config>`          | IG_DEFAULT      | takes changes at the next period boundary, an   |
|                              |                              |                 | observer at the next command.                   |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+
| msg_id_panel                 | t_msg_id_panel               | C_VVC_MSG_ID_P\ | VVC dedicated message ID panel. See             |
|                              |                              | ANEL_DEFAULT    | :ref:`vvc_framework_verbosity_ctrl` for how to  |
|                              |                              |                 | use verbosity control.                          |
+------------------------------+------------------------------+-----------------+-------------------------------------------------+

.. note::

    cmd/result queue parameters in the configuration record are unused and will be removed in v3.0, use instead the entity generic constants.

The configuration record can be accessed from the Central Testbench Sequencer through the shared variable array, e.g. ::

    shared_pwm_vvc_config(C_VVC_IDX).bfm_config.alignment := CENTER_ALIGNED;

Status Record
==================================================================================================================================
**vvc_status** accessible via **shared_pwm_vvc_status**

.. include:: rst_snippets/vip_vvc_status.rst

Methods
==================================================================================================================================
* All VVC procedures are defined in vvc_methods_pkg.vhd (dedicated to this VVC).
* See :ref:`vvc_framework_methods` for procedures which are common to all VVCs.
* It is also possible to send a multicast to all instances of a VVC with ALL_INSTANCES as parameter for vvc_instance_idx.
* All parameters in brackets are optional.
* Generator methods are only accepted by a GENERATOR instance, observer methods only by an OBSERVER instance, see
  :ref:`pwm_roles`.

.. note::

    A multicast with ALL_INSTANCES reaches every instance, whatever its role. If the testbench has both GENERATOR and OBSERVER
    instances, each instance of the other role raises an ERROR and skips the command. Use ALL_INSTANCES only for methods that
    all instances accept, e.g. the common VVC methods, or when all instances have the same role.

.. note::

    Some parameters in the VVC procedures are unconstrained for flexibility. However, the maximum sizes of such parameters need to
    be defined for the VVC framework. For this VVC, the following maximum values can be configured from adaptations_pkg:

      +--------------------------------------------+--------------------------------------+
      | C_PWM_VVC_CMD_STRING_MAX_LENGTH            | Maximum **msg** length               |
      +--------------------------------------------+--------------------------------------+
      | C_PWM_VVC_MAX_INSTANCE_NUM                 | Maximum number of VVC instances      |
      +--------------------------------------------+--------------------------------------+

.. _pwm_generate_vvc:

pwm_generate()
----------------------------------------------------------------------------------------------------------------------------------
Adds a generate command to the PWM VVC executor queue, which will run as soon as all preceding commands have completed.
The VVC generates num_periods complete periods, as the BFM :ref:`pwm_generate_bfm`, then drives the idle level. The
command completes at the end of the last period. GENERATOR role only. A TB_ERROR is raised if a continuous run is active.

.. code-block::

    pwm_generate(VVCT, vvc_instance_idx, period, active_time, num_periods, msg, [scope])
    pwm_generate(VVCT, vvc_instance_idx, period, duty, num_periods, msg, [scope])
    pwm_generate(VVCT, vvc_instance_idx, period, count, resolution, num_periods, msg, [scope])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | period             | in     | time                         | The PWM period T. Must be > 0 ns.                       |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The active time t_on. Must be within 0 ns to period.    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | duty               | in     | real                         | Duty cycle as ratio 0.0 to 1.0, converted to an active  |
|          |                    |        |                              | time rounded to the nearest simulator resolution unit   |
|          |                    |        |                              | (half a unit is rounded up).                            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | count              | in     | integer                      | Duty cycle as counter value, 0 to resolution            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | resolution         | in     | integer                      | Number of counter steps of the period, >= 1             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of complete periods to generate, >= 1            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_generate(PWM_VVCT, 1, 1 us, 250 ns, 10, "10 periods with 25 % duty", C_SCOPE);
    pwm_generate(PWM_VVCT, 1, 1 us, 0.25, 10, "10 periods with 25 % duty", C_SCOPE);
    pwm_generate(PWM_VVCT, 1, 1 us, 64, 256, 10, "10 periods with 64/256 duty", C_SCOPE);


.. _pwm_start_vvc:

pwm_start()
----------------------------------------------------------------------------------------------------------------------------------
Adds a start command to the PWM VVC executor queue. The VVC starts continuous generation, which runs until
:ref:`pwm_stop_vvc` or :ref:`pwm_abort_vvc`. The command completes when the first period begins, so the executor is free
for further commands while the waveform runs. GENERATOR role only. A TB_ERROR is raised if a run is already active.

.. code-block::

    pwm_start(VVCT, vvc_instance_idx, period, active_time, msg, [scope])
    pwm_start(VVCT, vvc_instance_idx, period, duty, msg, [scope])
    pwm_start(VVCT, vvc_instance_idx, period, count, resolution, msg, [scope])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | period             | in     | time                         | The PWM period T. Must be > 0 ns.                       |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The active time t_on. Must be within 0 ns to period.    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | duty               | in     | real                         | Duty cycle as ratio 0.0 to 1.0, converted to an active  |
|          |                    |        |                              | time rounded to the nearest simulator resolution unit   |
|          |                    |        |                              | (half a unit is rounded up).                            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | count              | in     | integer                      | Duty cycle as counter value, 0 to resolution            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | resolution         | in     | integer                      | Number of counter steps of the period, >= 1             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_start(PWM_VVCT, 1, 1 us, 0.5, "Start 1 MHz, 50 %", C_SCOPE);


.. _pwm_update_vvc:

pwm_update()
----------------------------------------------------------------------------------------------------------------------------------
Adds an update command to the PWM VVC executor queue. The new period and duty cycle of the continuous generation
take effect at the next period boundary; the current period is completed with the old values. The command completes when
the new values took effect. GENERATOR role only. A TB_ERROR is raised if no continuous run is active.

.. code-block::

    pwm_update(VVCT, vvc_instance_idx, period, active_time, msg, [scope])
    pwm_update(VVCT, vvc_instance_idx, period, duty, msg, [scope])
    pwm_update(VVCT, vvc_instance_idx, period, count, resolution, msg, [scope])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | period             | in     | time                         | The PWM period T. Must be > 0 ns.                       |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The active time t_on. Must be within 0 ns to period.    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | duty               | in     | real                         | Duty cycle as ratio 0.0 to 1.0, converted to an active  |
|          |                    |        |                              | time rounded to the nearest simulator resolution unit   |
|          |                    |        |                              | (half a unit is rounded up).                            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | count              | in     | integer                      | Duty cycle as counter value, 0 to resolution            |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | resolution         | in     | integer                      | Number of counter steps of the period, >= 1             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_update(PWM_VVCT, 1, 1 us, 0.75, "Change to 75 %", C_SCOPE);


.. _pwm_stop_vvc:

pwm_stop()
----------------------------------------------------------------------------------------------------------------------------------
Adds a stop command to the PWM VVC executor queue. The continuous generation ends at the next period boundary
(the current period is completed), then the VVC drives the idle level. The command completes when the line is idle.
GENERATOR role only. A TB_ERROR is raised if no run is active.

.. code-block::

    pwm_stop(VVCT, vvc_instance_idx, msg, [scope])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_stop(PWM_VVCT, 1, "Stop at the next period boundary", C_SCOPE);


.. _pwm_abort_vvc:

pwm_abort()
----------------------------------------------------------------------------------------------------------------------------------
Adds an abort command to the PWM VVC executor queue. The generation ends at once, possibly cutting the current
period short, and the VVC drives the idle level. GENERATOR role only. A TB_ERROR is raised if no run is active.
terminate_current_command() during a pwm_generate() command also aborts the generation.

.. code-block::

    pwm_abort(VVCT, vvc_instance_idx, msg, [scope])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_abort(PWM_VVCT, 1, "Abort now", C_SCOPE);


.. _pwm_measure_vvc:

pwm_measure()
----------------------------------------------------------------------------------------------------------------------------------
Adds a measure command to the PWM VVC executor queue, which will run as soon as all preceding commands have completed. When
the command is scheduled to run, the executor calls the BFM :ref:`pwm_measure_bfm` procedure with the VVC configuration.
OBSERVER role only.

The measurement will not be returned in this procedure call since it is non-blocking for the sequencer/caller, but it will
be stored in the VVC for a potential future fetch (see example with fetch_result below).

.. code-block::

    pwm_measure(VVCT, vvc_instance_idx, msg, [timeout, [scope]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_measure(PWM_VVCT, 2, "Measure the PWM output", 2 us, C_SCOPE);

    -- Example with fetch_result() call: Result is placed in v_result
    variable v_cmd_idx : natural;           -- Command index for the last measurement
    variable v_result  : t_pwm_measurement; -- Result of the measurement (t_vvc_result is a subtype of it)
    ...
    pwm_measure(PWM_VVCT, 2, "Measure the PWM output", 2 us);
    v_cmd_idx := get_last_received_cmd_idx(PWM_VVCT, 2);
    await_completion(PWM_VVCT, 2, v_cmd_idx, 10 us, "Wait for the measurement to finish");
    fetch_result(PWM_VVCT, 2, v_cmd_idx, v_result, "Fetching the measurement");

.. hint::

    :ref:`t_vvc_result` is defined in the corresponding vvc_cmd_pkg.vhd for the VIP, as a subtype of
    :ref:`t_pwm_measurement <t_pwm_measurement>`. vvc_context does not include vvc_cmd_pkg, so use t_pwm_measurement in the
    testbench.


.. _pwm_check_vvc:

pwm_check()
----------------------------------------------------------------------------------------------------------------------------------
Adds a check command to the PWM VVC executor queue, which will run as soon as all preceding commands have completed.
When the command is scheduled to run, the executor calls the BFM :ref:`pwm_check_bfm` procedure with the VVC
configuration. OBSERVER role only.

.. code-block::

    pwm_check(VVCT, vvc_instance_idx, period, active_time, msg, [num_periods, [alert_level, [timeout, [scope]]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | period             | in     | time                         | The expected period. Must be > 0 ns.                    |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | active_time        | in     | time                         | The expected active time, 0 ns to period                |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of consecutive periods to check. Default value   |
|          |                    |        |                              | is 1.                                                   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | alert_level        | in     | :ref:`t_alert_level`         | Sets the severity for the alert. Default value is       |
|          |                    |        |                              | ERROR.                                                  |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_check(PWM_VVCT, 2, 1 us, 250 ns, "Check one period");
    pwm_check(PWM_VVCT, 2, 1 us, 250 ns, "Check 5 periods", 5, ERROR, 2 us, C_SCOPE);


.. _pwm_check_duty_vvc:

pwm_check_duty()
----------------------------------------------------------------------------------------------------------------------------------
Adds a duty-check command to the PWM VVC executor queue, which will run as soon as all preceding commands have
completed. When the command is scheduled to run, the executor calls the BFM :ref:`pwm_check_duty_bfm` procedure with the
VVC configuration. OBSERVER role only.

.. code-block::

    pwm_check_duty(VVCT, vvc_instance_idx, duty, msg, [num_periods, [alert_level, [timeout, [scope]]]])

+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| Object   | Name               | Dir.   | Type                         | Description                                             |
+==========+====================+========+==============================+=========================================================+
| signal   | VVCT               | inout  | t_vvc_target_record          | VVC target type compiled into each VVC in order to      |
|          |                    |        |                              | differentiate between VVCs                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | vvc_instance_idx   | in     | integer                      | Instance number of the VVC                              |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | duty               | in     | real                         | The expected duty cycle, 0.0 to 1.0                     |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | msg                | in     | string                       | A custom message to be appended in the log/alert        |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | num_periods        | in     | integer                      | Number of consecutive periods to check. Default value   |
|          |                    |        |                              | is 1.                                                   |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | alert_level        | in     | :ref:`t_alert_level`         | Sets the severity for the alert. Default value is       |
|          |                    |        |                              | ERROR.                                                  |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | timeout            | in     | time                         | Maximum wait for each required edge. Default value is   |
|          |                    |        |                              | C_UNDEFINED_TIME, which leads to using config.timeout.  |
|          |                    |        |                              | 0 ns means no timeout. See :ref:`pwm_timeout`.          |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+
| constant | scope              | in     | string                       | Describes the scope from which the log/alert            |
|          |                    |        |                              | originates. Default value is C_VVC_CMD_SCOPE_DEFAULT    |
|          |                    |        |                              | defined in adaptations_pkg.                             |
+----------+--------------------+--------+------------------------------+---------------------------------------------------------+

.. code-block::

    -- Examples:
    pwm_check_duty(PWM_VVCT, 2, 0.25, "Check 25 % duty over 10 periods", 10, ERROR, 2 us, C_SCOPE);


.. _pwm_roles:

Roles and generator run state
==================================================================================================================================
* A VVC instance is either a GENERATOR or an OBSERVER (generic GC_ROLE). To drive and measure the same line, use two
  instances on one signal: the observer always drives 'Z'.
* A command for the other role raises an ERROR alert and is skipped.
* The generator waveform runs in its own process, so pwm_update(), pwm_stop() and pwm_abort() are accepted while a
  continuous run started by pwm_start() is active. After pwm_start() has completed, the VVC executor is inactive although
  the waveform keeps running (this matters for :ref:`vvc_framework_activity_watchdog` and await_uvvm_completion()).
* Run-state errors raise a TB_ERROR and leave the line unchanged: pwm_start() while a run is active, pwm_update(),
  pwm_stop() or pwm_abort() without a run, pwm_generate() during a continuous run.
* Invalid duty or count/resolution values raise a TB_ERROR in the method and the command is not queued. Invalid period,
  active_time, num_periods and config.jitter values raise a TB_ERROR in the executor and the command is skipped.
* Changes of shared_pwm_vvc_config(idx).bfm_config take effect at the next period boundary. A negative config.jitter set
  during a run raises one TB_ERROR, and the run keeps the previous configuration.
* "Next period boundary" means the next boundary after the request reaches the VVC. A pwm_update(), pwm_stop() or
  configuration change issued at the same simulation time as a period boundary may take effect only at the following
  boundary, e.g. pwm_stop() issued exactly N periods after pwm_start() can give N+1 periods. Issue such requests before the
  boundary time.
* The idle level is driven from GC_PWM_BFM_CONFIG at time 0 and from the current configuration at the end of each run.
* terminate_current_command() during pwm_generate() aborts the generation. During pwm_update() or pwm_stop() it ends the
  wait only; the request stays pending. During an observer command it ends the observation at once, without an alert.
* insert_delay() with a number of clock cycles raises a TB_ERROR, as the VVC has no clock. Use a time.


Activity Watchdog
==================================================================================================================================
.. include:: rst_snippets/vip_activity_watchdog.rst


Transaction Info
==================================================================================================================================
.. include:: rst_snippets/vip_transaction_info.rst

.. table:: PWM transaction info record fields. Transaction Type: t_base_transaction (BT) - accessible via **shared_pwm_vvc_transaction_info.bt**

    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | Info field                   | Type                         | Default         | Description                                     |
    +==============================+==============================+=================+=================================================+
    | operation                    | t_operation                  | NO_OPERATION    | Current VVC operation, e.g. GENERATE_PERIODS,   |
    |                              |                              |                 | START, UPDATE, STOP, ABORT, MEASURE, CHECK,     |
    |                              |                              |                 | CHECK_DUTY                                      |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | period                       | time                         | 0 ns            | Generator: the generated period. Observer: the  |
    |                              |                              |                 | expected period.                                |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | active_time                  | time                         | 0 ns            | Generator: the generated active time. Observer: |
    |                              |                              |                 | the expected active time.                       |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | duty                         | real                         | 0.0             | CHECK_DUTY: the expected duty cycle             |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | num_periods                  | integer                      | 0               | GENERATE_PERIODS, CHECK, CHECK_DUTY: number of  |
    |                              |                              |                 | periods. 0 otherwise.                           |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | vvc_meta                     | t_vvc_meta                   | C_VVC_META_DEF\ | VVC meta data of the executing VVC command      |
    |                              |                              | AULT            |                                                 |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    |  -> msg                      | string                       | ""              | Message of executing VVC command                |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    |  -> cmd_idx                  | integer                      | -1              | Command index of executing VVC command          |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+
    | transaction_status           | :ref:`t_transaction_status`  | INACTIVE        | Set to INACTIVE, IN_PROGRESS, FAILED or         |
    |                              |                              |                 | SUCCEEDED during a transaction                  |
    +------------------------------+------------------------------+-----------------+-------------------------------------------------+

* The operation GENERATE_PERIODS is used for pwm_generate(), because 'generate' is a VHDL reserved word.
* The transaction info of MEASURE carries no result; the measurement is fetched with fetch_result().
* Commands rejected for the wrong role, the run state or invalid parameters leave the transaction info unchanged.

More information can be found in :ref:`Essential Mechanisms - Distribution of Transaction Info <vvc_framework_transaction_info>`.


Scoreboard
==================================================================================================================================
This VVC has no Scoreboard functionality. Measurements are fetched with fetch_result(), see :ref:`pwm_measure_vvc`.


Unwanted Activity Detection
==================================================================================================================================
This VVC has no unwanted activity detection.


Compilation
==================================================================================================================================
The PWM VVC must be compiled with VHDL-2008 or newer. It is dependent on the following libraries:

    * UVVM Utility Library (UVVM-Util)
    * UVVM VVC Framework
    * PWM BFM

Before compiling the PWM VVC, assure that uvvm_util and uvvm_vvc_framework have been compiled.

See :ref:`Essential Mechanisms - Compile Scripts <vvc_framework_compile_scripts>` for information about compile scripts.

.. table:: Compile order for the PWM VVC

    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | Compile to library           | File                                           | Comment                                         |
    +==============================+================================================+=================================================+
    | p2l2_vip_pwm                 | pwm_bfm_pkg.vhd                                | PWM BFM                                         |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | transaction_pkg.vhd                            | PWM transaction package with DTT types,         |
    |                              |                                                | constants, etc.                                 |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | vvc_cmd_pkg.vhd                                | PWM VVC command types and operations            |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | ../uvvm_vvc_framework/src_target_dependent/td\ | UVVM VVC target support package, compiled into  |
    |                              | _target_support_pkg.vhd                        | this VVC library                                |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | ../uvvm_vvc_framework/src_target_dependent/td\ | Common UVVM framework methods compiled into the |
    |                              | _vvc_framework_common_methods_pkg.vhd          | this VVC library                                |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | vvc_methods_pkg.vhd                            | PWM VVC methods                                 |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | ../uvvm_vvc_framework/src_target_dependent/td\ | UVVM queue package for this VVC                 |
    |                              | _queue_pkg.vhd                                 |                                                 |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | ../uvvm_vvc_framework/src_target_dependent/td\ | UVVM VVC entity support compiled into this VVC  |
    |                              | _vvc_entity_support_pkg.vhd                    | library                                         |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | pwm_vvc.vhd                                    | PWM VVC                                         |
    +------------------------------+------------------------------------------------+-------------------------------------------------+
    | p2l2_vip_pwm                 | vvc_context.vhd                                | PWM VVC context file                            |
    +------------------------------+------------------------------------------------+-------------------------------------------------+

Simulator compatibility and setup
----------------------------------------------------------------------------------------------------------------------------------
.. include:: rst_snippets/simulator_compatibility.rst

The maintenance testbenches of this VIP have been run with Questa Altera Starter FPGA Edition 2025.3 (``-t ps``) and
GHDL 6.0.0.


.. include:: rst_snippets/ip_disclaimer.rst
