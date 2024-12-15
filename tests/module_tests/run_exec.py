import subprocess
import sys

def run_executable(executable_path, output_file, *args):
    """
    Runs an executable with optional arguments and writes its stdout and stderr to a specified file.

    :param executable_path: Path to the executable file
    :param output_file: Path to the output file
    :param args: Additional arguments to pass to the executable
    """
    try:
        # Open the output file in write mode
        with open(output_file, 'w') as file:
            # Run the executable with arguments
            process = subprocess.Popen(
                [executable_path, *args],
                stdout=file,
                stderr=file,
                text=True  # Ensures output is treated as text
            )
            # Wait for the process to complete
            process.wait()

            # Check the return code to determine if the process succeeded
            if process.returncode == 0:
                print(f"Execution completed successfully. Output written to {output_file}")
            else:
                print(f"Execution failed with return code {process.returncode}. Check {output_file} for details.")
    except FileNotFoundError:
        print(f"Error: File not found at {output_file}")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python run_executable.py <executable_path> <output_file> [args...]")
    else:
        executable_path = sys.argv[1]
        output_file = sys.argv[2]
        print(f"executable_path : {executable_path}");
        print(f"output file: {output_file}")
        args = sys.argv[3:]
        run_executable(executable_path, output_file, *args)
