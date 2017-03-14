module NLOptControl

using Media, Plots, VehicleModels, Dierckx, Parameters, Interpolations, FastGaussQuadrature, Polynomials, JuMP, SymPy, VehicleModels, DataFrames, Ipopt, KNITRO
# To copy a particular piece of code (or function) in some location
macro def(name, definition)
  return quote
    macro $name()
      esc($(Expr(:quote,definition)))
    end
  end
end

################################################################################
# Basic Types
################################################################################
############################### control ########################################
type Control #TODO correlate these with JuMP variables
  name::Vector{Any}
  description::Vector{Any}
end
function Control()
  Control([],
          []);
end

# ############################# state  ##########################################
type State #TODO correlate these with JuMP variables
  # constants
  name::Vector{Any}
  description::Vector{Any}
end
function State()
  State([],
        []);
end

############################## constraint ######################################
type Constraint
  name::Vector{Any}
  handle::Vector{Any}
  value::Vector{Any}
  nums  # range of indecies in g(x)
end
function Constraint()
  Constraint([],
             [],
             [],
             []);
end

############################## mpc #############################################
type MPC
  # constants
  tp::Float64          # predication time (if finalTimeDV == true -> this is not known before optimization)
  tex::Float64         # execution horizon time
  max_iter::Int64      # maximum number of iterations

  # variables
  goal_reached::Bool           # flag  to indicate that goal has been reached
  t0::Float64                  # inital time
  tf::Float64                  # final time
  X0p::Array{Float64,1}        # predicted initial states
  u::Array{Array{Float64,1},1} # all control signals
end

function MPC()
  MPC(0.0,
      0.0,
      0,
      false,
      0.0,
      0.0,
      Float64[],          # predicted intial state conditions
      Vector{Float64}[]);
end

################################################################################
# Model Class
################################################################################
abstract AbstractNLOpt
type NLOpt <: AbstractNLOpt
  # general properties
  stateEquations
  numStates::Int64          # number of states
  state::State              # state data
  numControls::Int64        # number of controls
  control::Control          # control data
  numPoints::Array{Int64,1} # number of dv discretization within each interval
  numStatePoints::Int64     # number of dvs per state
  numControlPoints::Int64   # numer of dvs per control
  lengthDV::Int64           # total number of dv discretizations per variables
  tf::Any                   # final time
  t0::Any                   # initial time
  tf_max::Any               # maximum final time

  # boundary constraits
  X0::Array{Float64,1}      # initial state conditions
  X0_tol::Array{Float64,1}  # initial state tolerance
  XF::Array{Float64,1}      # final state conditions
  XF_tol::Array{Float64,1}  # final state tolerance

  # linear bounds on variables
  XL::Array{Float64,1}
  XU::Array{Float64,1}
  CL::Array{Float64,1}
  CU::Array{Float64,1}

  # ps method data
  Nck::Array{Int64,1}           # number of collocation points per interval
  Ni::Int64                     # number of intervals
  τ::Array{Array{Float64,1},1}  # Node points ---> Nc increasing and distinct numbers ∈ [-1,1]
  ts::Array{Array{Any,1},1}     # time scaled based off of τ
  ω::Array{Array{Float64,1},1}  # weights
  ωₛ::Array{Array{Any,1},1}     # scaled weights
  DMatrix::Array{Array{Any,2},1}# differention matrix
  IMatrix::Array{Array{Any,2},1}# integration matrix

  # tm method data
  N::Int64                      # number of points in discretization
  dt::Array{Any,1}              # array of dts

  # bools
  define::Bool

  # mpc data
  mpc::MPC

  # options
  finalTimeDV::Bool
  integrationMethod::Symbol
  integrationScheme::Symbol
  solver::Symbol                 # solver
end

# Default Constructor
function NLOpt()
NLOpt(Any,                # state equations
      0,                  # number of states
      State(),            # state data
      0,                  # number of controls
      Control(),          # control data
      Int[],              # number of dv discretization within each interval
      0,                  # number of dvs per state
      0,                  # number of dvs per control
      0,                  # total number of dv discretizations per variables
      Any,                # final time
      Any,                # initial time
      Any,                # maximum final time
      Float64[],          # initial state conditions
      Float64[],          # tolerances on inital state constraint
      Float64[],          # final state conditions
      Float64[],          # tolerances on final state constraint
      Float64[],          # XL
      Float64[],          # XU
      Float64[],          # CL
      Float64[],          # CU
      Int[],              # number of collocation points per interval
      0,                  # number of intervals
      Vector{Float64}[],  # τ
      Vector{Any}[],      # ts
      Vector{Float64}[],  # weights
      Vector{Any}[],      # scaled weights
      Matrix{Any}[],      # DMatrix
      Matrix{Any}[],      # IMatrix
      0,                  # number of points in discretization
      Any[],              # array of dts
      false,              # bool to indicate if problem has been defined
      MPC(),              # mpc data
      false,              # finalTimeDV
      :ts,                # integrtionMethod
      :bkwEuler,          # integrationScheme
      :IPOPT              # default solver
    );
end

# Result Class
abstract AbstractNLOpt
type Result <: AbstractNLOpt
  t_ctr                       # time vector for control
  t_st                        # time vector for state
  x                           # JuMP states
  u                           # JuMP controls
  X                           # states
  U                           # controls
  x0_con                      # handle for intial state constraints
  xf_con                      # handle for final state constraints
  dyn_con                     # dynamics constraints
  constraint::Constraint      # constraint handels and data
  eval_num::Int64             # number of times optimization has been run
  iter_nums::Vector{Any}      # mics. data, perhaps an iteration number for a higher level algorithm
  status::Vector{Symbol}      # optimization status
  t_solve::Vector{Float64}    # solve time for optimization
  obj_val::Vector{Float64}    # objective function value
  dfs                         # results in DataFrame for plotting
  dfs_opt                     # optimization information in DataFrame for plotting
  dfs_plant                   # plant data
  dfs_con                     # constraint data
  results_dir                 # string that defines results folder
end

# Default Constructor
function Result()
Result( Vector{Any}[], # time vector for control
        Vector{Any}[], # time vector for state
        Matrix{Any}[], # JuMP states
        Matrix{Any}[], # JuMP controls
        Matrix{Any}[], # states
        Matrix{Any}[], # controls
        nothing,       # handle for intial state constraints
        nothing,       # handle for final state constraints
        nothing,       # dynamics constraint
        Constraint(),  # constraint data  TODO consider moving this
        0,             # number of times optimization has been run
        [],            # mics. data, perhaps an iteration number for a higher level algorithm
        Symbol[],      # optimization status
        Float64[],     # solve time for optimization
        Float64[],     # objective function value
        [],            # results in DataFrame for plotting
        [],            # optimization information in DataFrame for plotting
        [],            # plant data
        [],            # constraint data
        "/results/",   # string that defines results folder
      );
end

# Settings Class
abstract AbstractNLOpt
type Settings <: AbstractNLOpt
  # plotting
  lw1::Float64   # line width 1
  lw2::Float64   # line width 2
  ms1::Float64   # marker size 1
  ms2::Float64   # marker size 2
  s1::Int64      # size of figure
  s2::Int64      # size of figure
  simulate::Bool # bool for simulation
  L::Int64       # length for plotting points
  format::Symbol # format for output plots
  MPC::Bool      # bool for doing MPC
  save::Bool     # bool for saving data
  reset::Bool    # bool for reseting data
end

# Default Constructor
function Settings(;format::Symbol=:png,MPC::Bool=false,save::Bool=true,reset::Bool=false,simulate::Bool=false)  # consider moving these plotting settings to PrettyPlots.jl
Settings(5.5,    # line width 1
         3.,     # line width 2
         1.0,    # marker size 1
         5.0,    # marker size 2
         700,    # size of figure
         1000,   # size of figure
         simulate,  # bool for simulations
         100,    # length for plotting points
         format, # format for output plots
         MPC,    # bool for doing MPC
         save,   # bool for saving data
         reset   # bool for reseting data
        );
end

# scripts
include("utils.jl");
include("setup.jl")
include("ps.jl");
include("ocp.jl")
include("post_processing.jl")
include("PrettyPlots.jl")
       # Functions
export
       # setup functions
       NLOpt, define, configure,
       OCPdef,

       # ps functions
       LGR_matrices,
       scale_tau, scale_w, createIntervals,
       lagrange_basis_poly, interpolate_lagrange,
       polyDiff,
       D_matrix,

       # math functions
       integrate,

       # optimization related functions
       optimize,
       defineTolerances,
       defineSolver,
       build,

       # data processing
       postProcess,
       newConstraint,
       evalConstraints,
       evalMaxDualInf,
       stateNames,
       controlNames,
       dvs2dfs,
       plant2dfs,
       opt2dfs,

       # MPC
       simPlant,
       mpcParams,
       mpcUpdate,
       updateX0,

       # Objects
       NLOpt,
       Result,
       Settings,

       # Plotting
       adjust_axis,
       resultsDir,
       statePlot,
       controlPlot,
       allPlots
end
