import sys
import os
import shutil

# Clean the sim directory
def cleanup(msg='Cleaning up...'):
    print(msg)
    sim_path = os.getcwd()
    # Check if the current directory is 'sim'
    if os.path.basename(sim_path) == 'sim':
        for files in os.listdir(sim_path):
            path = os.path.join(sim_path, files)
            try:
                shutil.rmtree(path)
            except:
                os.remove(path)
    else:
        print('Current directory is not "sim". Skipping cleanup.')


# Keep the simulation output (e.g. the wave file) when waves or the GUI are requested
keep_output = any(arg in sys.argv for arg in ["--wlf", "-g", "--gui"])

print('Verify p2l2_vip_pwm')

# HDLRegression writes its output to the current directory and the .do-script check expects to run in sim:
# always run in p2l2_vip_pwm/sim, wherever the script is started from
sim_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sim'))
os.makedirs(sim_dir, exist_ok=True)
os.chdir(sim_dir)

cleanup('Removing any previous runs.')

# Imported after the cleanup: a kept output folder 'hdlregression' in sim would otherwise shadow the package
try:
    from hdlregression import HDLRegression
except:
    print('Unable to import HDLRegression module. See HDLRegression documentation for installation instructions.')
    sys.exit(1)

hr = HDLRegression()

# Add util and fw
hr.add_files("../../../uvvm_util/src/*.vhd", "uvvm_util")
hr.add_files("../../../uvvm_vvc_framework/src/*.vhd", "uvvm_vvc_framework")
# Add p2l2_vip_pwm VIP
hr.add_files("../../src/*.vhd", "p2l2_vip_pwm")
hr.add_files("../../../uvvm_vvc_framework/src_target_dependent/*.vhd", "p2l2_vip_pwm")
# Add TB/TH
hr.add_files("../../tb/maintenance_tb/*.vhd", "p2l2_vip_pwm")

# Set simulator name and options
# The tests use periods of a few resolution units and sub-ns edges, so ModelSim/Questa needs ps resolution.
sim_options = None
simulator_name = hr.settings.get_simulator_name()
if simulator_name == "MODELSIM":
    sim_options = "-t ps"
elif simulator_name in ["GHDL"]:
    com_options = ["--ieee=standard", "--std=08", "-frelaxed-rules", "-Wall", "--warn-no-shared", "--warn-no-hide", "--warn-no-delayed-checks"]
    hr.set_simulator(simulator=simulator_name, com_options=com_options)
elif simulator_name == "RIVIERA-PRO":
    com_options = ["-2008", "-nowarn", "COMP96_0564", "-nowarn", "COMP96_0048", "-nowarn", "DAGGEN_0001"]
    com_options += ["-O0"] # Needs optimization level 0 to avoid optimizing away some testbench signals
    hr.set_simulator(simulator=simulator_name, com_options=com_options)

hr.start(sim_options=sim_options)

num_failing_tests = hr.get_num_fail_tests()
num_passing_tests = hr.get_num_pass_tests()

# No tests run error
if num_passing_tests == 0:
    sys.exit(1)
# Remove output only if OK
if hr.check_run_results(exp_fail=0) is True and not keep_output:
    cleanup('Removing simulation output')

# Run alternative simulation scripts
if (simulator_name == "MODELSIM" or simulator_name == "RIVIERA-PRO") and not keep_output:
    print('\nVerify .do scripts...')
    (ret_txt, ret_code) = hr.run_command(["vsim", "-c", "-do", "do ../script/compile_src.do ../../uvvm_util ../../uvvm_util/sim; exit"], False)
    (ret_txt, ret_code) = hr.run_command(["vsim", "-c", "-do", "do ../script/compile_bfm.do; exit"], False)
    if ret_code == 0:
        print("TCL script test completed")
        if hr.check_run_results(exp_fail=0) is True:
            cleanup('Removing simulation output\n')
    else:
        print(ret_txt)
        num_failing_tests += 1

# Return number of failing tests
sys.exit(num_failing_tests)
