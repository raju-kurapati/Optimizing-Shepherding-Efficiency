from pathlib import Path
from multiprocessing import Pool
import pandas as pd
import numpy as np
import pynetlogo
from enum import Enum
from itertools import repeat
import logging
import time
import os
from typing import Optional
import jpype
from jpype._core import JVMNotRunning

from utils import *
from sample import sample, Parameter, SampledParameter, Sampler, Compare
from plotting import plot_parameter_sweep


netlogo: pynetlogo.NetLogoLink


class ShepherdModel(Enum):
    """Shepherd model choices"""

    STROMBOM = '"strombom"'
    PIERSON = '"pierson"'


def initializer(modelfile):
    """initialize a subprocess

    Parameters
    ----------
    modelfile: str, Path
        path to the netlogo model
    """
    # we need to set the instantiated netlogolink as a global so run_simulation can use it
    # create console handler and set level to debug

    log = logging.getLogger(__name__)
    log.setLevel(logging.DEBUG)

    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)

    # create formatter
    formatter = logging.Formatter(
        "%(asctime)s - %(processName)s - %(message)s", datefmt="%H:%M:%S"
    )

    # add formatter to ch
    ch.setFormatter(formatter)

    # add ch to logger
    log.addHandler(ch)

    global netlogo
    jvm_path = (
        Path(pynetlogo.core.get_netlogo_home())
        / "runtime"
        / "bin"
        / "client"
        / "jvm.dll"
    )
    netlogo = pynetlogo.NetLogoLink(gui=False, jvm_path=f"{jvm_path}")

    netlogo.load_model(f"{modelfile}")
    netlogo.command("setup")
    netlogo.command("reset-default-parameters")

    log.info(f"Started worker with PID {os.getpid()}")

    global start_time
    start_time = time.time()


def setup_simulation(experiment: dict, **model_parameters):
    """run a netlogo model until it finishes or max_ticks ticks

    Arguments
    ---------
    netlogo: pynetlogo.NetLogoLink
        netlogo link with the model loaded
    experiments: dict
        dictionary of experiment parameters

    Keyword Arguments
    -----------------
    model_parameters: dict
        additional keyword parameters to the model
    """
    # Set the input parameters
    for key, value in experiment.items():
        if key == "random_seed":
            # The NetLogo random seed requires a different syntax
            netlogo.command(f"random-seed {value}")
        else:
            # Otherwise, assume the input parameters are global variables
            netlogo.command(f"set {py2nl(key)} {value}")
    # Set the static model parameters
    for key, value in model_parameters.items():
        netlogo.command(f"set {py2nl(key)} {value}")
    netlogo.command("setup")


def run_time_trial(
    experiment, max_ticks=6000, iteration=0, num_experiments=1, **model_parameters
):
    """run a netlogo model until it finishes or max_ticks ticks

    Arguments
    ---------
    experiments: dict
        dictionary of experiment parameters

    Keyword Arguments
    -----------------
    max_ticks: int, default=8000
        maximum timesteps before halting the experiment
    model_parameters: dict, optional
        additional keyword parameters to set up the model

    Returns
    -------
    results: pd.Series
        results of the experiment
    """
    # Set the input parameters
    setup_simulation(experiment, **model_parameters)
    # Run until the model finishes or max_ticks ticks
    stop = False
    final_tick = 0
    # data = np.empty((max_ticks, 5))
    total_time = 0
    i = 0
    while not stop:
        start = time.process_time()
        netlogo.command("go")
        stop = netlogo.report(f"win? or ticks >= {max_ticks}")
        # data[i, 0] = netlogo.report("ticks")
        # data[i, 1] = netlogo.report("average-spread-global")
        # data[i, 2] = netlogo.report("max-spread-global")
        # data[i, 3] = netlogo.report("gcm-distance-from-goal")
        # data[i, 4] = netlogo.report("average-distance-from-goal")
        total_time += time.process_time() - start
        i += 1

    final_tick = np.int32(netlogo.report("ticks"))

    avg_spread = netlogo.report("average-spread-global")
    max_spread = netlogo.report("max-spread-global")
    gcm_dist = netlogo.report("gcm-distance-from-goal")
    avg_dist = netlogo.report("average-distance-from-goal")

    # logging.getLogger(__name__).debug(
    #     f"[N={experiment['num_sheep']:d}, n={experiment['num_neighbors']:d}, m={experiment['num_shepherds']:d}] final tick: {final_tick}, avg. tick/s: {final_tick/total_time:.2f}, time: {total_time:.2f}s"
    # )
    logging.getLogger(__name__).debug(
        f"Finished experiment {iteration}/{num_experiments} ({iteration/num_experiments:.2%}) in {time.time() - start_time:.2f}s"
    )

    final_results = pd.Series(
        [
            final_tick,
            final_tick < max_ticks,
            avg_spread,
            max_spread,
            gcm_dist,
            avg_dist,
        ],
        index=[
            "Final tick",
            "Win?",
            "Final Average Spread",
            "Final Max Spread",
            "Final GCM Distance from Goal",
            "Final Average Distance from Goal",
        ],
    )
    # time_series_results = pd.DataFrame(
    #     data[:i, :],
    #     columns=[
    #         "Tick",
    #         "Average Spread",
    #         "Max Spread",
    #         "GCM Distance from Goal",
    #         "Average Distance from Goal",
    #     ],
    # )
    return final_results
    # return experiment, final_results, time_series_results


def parameter_sweep_time_trial(
    modelfile,
    shepherd_model: ShepherdModel,
    parameters: list,
    constraints: Optional[list] = None,
    max_ticks=6000,
    num_processes=4,
    seed=None,
):
    """run a parameter sweep

    Arguments
    ---------
        modelfile: str, Path
            path to the netlogo model
        shepherd_model: ShepherdModel
            which shepherd model to use
        parameters: list
            list of parameters to sweep


    Keyword Arguments
    -----------------
        constraints: list, optional
            list of constraints to apply to the parameter sweep
        max_ticks: int, default=8000
            maximum timesteps before halting each run
        num_processes: int, default=4
            number of processes to use

    Returns
    -------
        problem: pd.DataFrame
            problem definition for the parameter sweep
        final_results: pd.DataFrame
            results of the parameter sweep
        time_series_results: pd.DataFrame
            time series results of the parameter sweep
    """
    start_time = time.time()
    log = logging.getLogger(__name__)
    experiments = sample(parameters, constraints, resample=True, seed=seed)
    print(experiments.head(32))

    num_experiments = len(experiments.index)

    log.info(f"Running {num_experiments} experiments...")
    with Pool(
        num_processes, initializer=initializer, initargs=(modelfile,)
    ) as executor:
        results = []
        i = 0
        # time_series = {}
        for result in starstarmap(
            executor,
            run_time_trial,
            zip(
                experiments.to_dict("records"),
                repeat(max_ticks),
                range(1, num_experiments + 1),
                repeat(num_experiments),
            ),
            repeat(dict(shepherd_model=f"{shepherd_model.value}")),
        ):
            # experiment = tuple(result[0].values())
            results.append(result)
            # time_series[experiment] = result[2]
        results_df = experiments.join(pd.DataFrame(results), how="left")
        results_df.set_index(experiments.columns.to_list(), inplace=True)
        # ts_df = pd.concat(time_series, names=experiments.columns.to_list())
    log.debug(f"Results:\n{results_df}")
    log.info(f"Ran {len(experiments)} experiments successfully!")
    return results_df  # , ts_df


if __name__ == "__main__":
    log = logging.getLogger(__name__)
    log.setLevel(logging.DEBUG)

    # create console handler and set level to debug
    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)

    # create formatter
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # add formatter to ch
    ch.setFormatter(formatter)

    # add ch to logger
    log.addHandler(ch)

    modelfile = Path.cwd() / "models" / "Shepherds.nlogo"
    initializer(modelfile)

    parameters = [
        SampledParameter("num-sheep", Sampler.LINEARINT, bounds=(1, 101), num=11),
        SampledParameter("num-neighbors", Sampler.LINEARINT, bounds=(1, 100), num=11),
        SampledParameter("num-shepherds", Sampler.LINEARINT, bounds=(2, 16), num=15),
        SampledParameter("random-seed", Sampler.RANDINT, bounds=(1, 100000), num=12),
    ]

    constraints = [Compare("num-sheep", ">=", "num-neighbors")]

    # final_results, ts_results = parameter_sweep_time_trial(
    final_results = parameter_sweep_time_trial(
        modelfile,
        ShepherdModel.PIERSON,
        parameters,
        constraints=constraints,
        num_processes=18,
        seed=42,
    )

    from pickle import dumps

    results_file = Path("results.pkl")
    results_file.write_bytes(dumps(((parameters, constraints), final_results)))

    log.info(f"Plotting results...")
    fig, _ = plot_parameter_sweep(results_file)
    fig.savefig("results.png", dpi=300)
    log.info(f"Plotting completed successfully!")

    netlogo.kill_workspace()
